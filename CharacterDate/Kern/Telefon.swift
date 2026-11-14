import Foundation
import AVFoundation
import Observation
import UIKit

/// Echtzeit-Telefonat mit dem Kern (gleiches Protokoll wie am PC, siehe core/cd/anruf.py):
/// Mikrofon → PCM16 mono 16 kHz als Binärrahmen; ihre Stimme kommt als PCM16 mono (Abtastrate aus »ton«).
/// Echo-Unterdrückung übernimmt die Voice-Processing-Einheit von iOS. Ohne CallKit: iOS hat den Anruf dort
/// abgelehnt und mit »providerDidReset« jeden Anruf sofort wieder beendet (Log 14.11.) – die App führt ihn selbst.
@Observable
final class Telefon {
    /// Läuft gerade irgendein Anruf? (Dann verbindet die App nicht neu und sperrt nicht.)
    nonisolated(unsafe) static var laeuft = false
    enum Zustand: String { case waehlt, klingelt, aktiv, beendet }

    var zustand: Zustand = .waehlt
    var info: String?
    var grund: String?
    var start: Date?
    var stumm = false
    var lautsprecher = false
    var sieText = ""
    var duText = ""
    var pegelDu: Float = 0
    var pegelSie: Float = 0
    /// Gesprächsverlauf fürs Chatfenster im Anruf (gesprochen und getippt).
    struct Zeile: Identifiable, Equatable { let id = UUID(); let sie: Bool; var text: String; var zeit = Date() }
    var verlauf: [Zeile] = []

    private var socket: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    private let stimme = AVAudioPlayerNode()
    private let freizeichen = AVAudioPlayerNode()
    private var stimmFormat: AVAudioFormat?
    private var wandler: AVAudioConverter?
    private let zielFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var audioLaeuft = false
    private var verbindung: Verbindung?
    private var charId = ""

    // MARK: Start / Ende

    @ObservationIgnored var eingehend = false

    @MainActor
    func starten(_ v: Verbindung, char: Charakter, eingehend: Bool = false, video: Bool = false) {
        self.eingehend = eingehend
        Telefon.laeuft = true
        verbindung = v
        charId = char.id
        // Telefonat: Hörmuschel (Handy ans Ohr, Display aus); Videoanruf: Lautsprecher
        lautsprecher = video
        sitzungEinrichten()
        do { try AVAudioSession.sharedInstance().setActive(true) }
        catch { letzterFehler = "Audio-Sitzung: \(error.localizedDescription)"; melden(letzterFehler!) }
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(lautsprecher ? .speaker : .none)
        audioStarten()
        freizeichenStarten()                 // »tuut … tuut« schon beim Wählen, bis sie wirklich dran ist
        UIDevice.current.isProximityMonitoringEnabled = !lautsprecher
        verbinden()
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // Kopfhörer/Bluetooth ab- oder angesteckt: gewählte Ausgabe beibehalten
            guard let self, self.zustand != .beendet, self.lautsprecher else { return }
            try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        }
    }

    @MainActor
    func auflegen() { beenden() }

    @MainActor
    func stummSchalten() { setzeStumm(!stumm) }

    @MainActor
    func setzeStumm(_ an: Bool) {
        stumm = an
        senden(["typ": "stumm", "an": an])
    }

    @MainActor
    func lautsprecherSchalten() {
        lautsprecher.toggle()
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(lautsprecher ? .speaker : .none)
        UIDevice.current.isProximityMonitoringEnabled = !lautsprecher && zustand != .beendet
    }

    /// Räumt alles ab (aus CallKit-Ende, Fehler oder Serverende).
    /// Fehlersuche: warum ein Anruf endete, landet im Log des PCs.
    @ObservationIgnored var letzterFehler: String?
    func melden(_ text: String) {
        guard let v = verbindung else { return }
        struct P: Encodable { let quelle: String; let text: String }
        struct A: Decodable { let ok: Bool }
        Task { let _: A? = try? await v.anfrage("/api/protokoll", methode: "POST", body: P(quelle: "iPhone-Anruf", text: text)) }
    }

    @MainActor
    func beenden(grund g: String? = nil) {
        Telefon.laeuft = false
        if let g, grund == nil { grund = g }
        if zustand != .beendet {
            let dauer = start.map { Int(Date().timeIntervalSince($0)) } ?? 0
            melden("Anruf endet: Zustand \(zustand), Grund \(g ?? "–"), nach \(dauer) s, letzter Fehler \(letzterFehler ?? "–")")
        }
        if zustand != .beendet {
            senden(["typ": "auflegen"])
            zustand = .beendet
        }
        let s = socket
        socket = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { s?.cancel(with: .normalClosure, reason: nil) }
        audioStoppen()
        UIDevice.current.isProximityMonitoringEnabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Verbindung

    func sitzungEinrichten() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
        try? s.setPreferredIOBufferDuration(0.02)
    }

    func verbinden() {
        guard socket == nil, let v = verbindung, let s = v.anrufSocket(charId, eingehend: eingehend) else {
            Task { @MainActor in self.beenden(grund: "Keine Verbindung zum PC.") }
            return
        }
        socket = s
        s.resume()
        empfangen(s)
    }

    /// Ihre Augen: Kamera an/aus melden und Standbilder schicken.
    func kameraMelden(_ an: Bool) { senden(["typ": "kamera", "an": an]) }
    /// Getippt statt gesprochen – sie antwortet trotzdem mit Stimme.
    func textSenden(_ t: String) { senden(["typ": "text", "text": t]) }
    func blickSenden(_ dataURL: String) { senden(["typ": "blick", "bild": dataURL]) }

    private func senden(_ d: [String: Any]) {
        guard let s = socket, let daten = try? JSONSerialization.data(withJSONObject: d),
              let text = String(data: daten, encoding: .utf8) else { return }
        s.send(.string(text)) { _ in }
    }

    private func empfangen(_ s: URLSessionWebSocketTask) {
        s.receive { [weak self] ergebnis in
            guard let self, self.socket === s else { return }
            switch ergebnis {
            case .failure(let f):
                self.letzterFehler = "WebSocket: \(f.localizedDescription) (Code \(s.closeCode.rawValue))"
                Task { @MainActor in if self.zustand != .beendet { self.beenden(grund: "Verbindung zum PC unterbrochen.") } }
            case .success(let n):
                switch n {
                case .data(let d): self.stimmeAbspielen(d)
                case .string(let t): Task { @MainActor in self.nachricht(t) }
                @unknown default: break
                }
                self.empfangen(s)
            }
        }
    }

    @MainActor
    private func nachricht(_ t: String) {
        guard let d = (try? JSONSerialization.jsonObject(with: Data(t.utf8))) as? [String: Any],
              let typ = d["typ"] as? String else { return }
        switch typ {
        case "status":
            let z = d["zustand"] as? String ?? ""
            if let i = d["info"] as? String { info = i }
            switch z {
            case "klingelt", "verbindet":
                zustand = .klingelt
                freizeichenStarten()
            case "aktiv":
                freizeichen.stop()
                info = nil
                zustand = .aktiv
                start = Date()
                UIDevice.current.isProximityMonitoringEnabled = !lautsprecher
            case "verpasst", "beendet":
                beenden(grund: d["grund"] as? String ?? (z == "verpasst" ? "Nicht erreicht." : nil))
            default: break
            }
        case "sie":
            let t = d["text"] as? String ?? ""
            sieText = t
            // Sätze einer Antwort in einer Blase sammeln
            if let l = verlauf.last, l.sie, Date().timeIntervalSince(l.zeit) < 6 {
                verlauf[verlauf.count - 1].text += " " + t
                verlauf[verlauf.count - 1].zeit = Date()
            } else if !t.isEmpty { verlauf.append(Zeile(sie: true, text: t)) }
        case "du":
            let t = d["text"] as? String ?? ""
            duText = t
            if !t.isEmpty { verlauf.append(Zeile(sie: false, text: t)) }
        case "ton":
            if let sr = d["sr"] as? Double { stimmFormatSetzen(sr) }
            else if let sr = d["sr"] as? Int { stimmFormatSetzen(Double(sr)) }
        case "stopp":
            // Du hast dazwischengesprochen: ihre Stimme sofort verstummen lassen
            stimme.stop()
            if audioLaeuft { stimme.play() }
            pegelSie = 0
        case "fehler": info = d["text"] as? String
        default: break
        }
    }

    // MARK: Audio

    func audioStarten() {
        guard !audioLaeuft else { return }
        let ein = engine.inputNode
        try? ein.setVoiceProcessingEnabled(true)          // Echo-Unterdrückung + Rauschfilter
        engine.attach(stimme)
        engine.attach(freizeichen)
        let sf = stimmFormat ?? AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        stimmFormat = sf
        engine.connect(stimme, to: engine.mainMixerNode, format: sf)
        let fz = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.connect(freizeichen, to: engine.mainMixerNode, format: fz)

        let eingang = ein.outputFormat(forBus: 0)
        guard eingang.sampleRate > 0, eingang.channelCount > 0 else {
            Task { @MainActor in self.beenden(grund: "Kein Mikrofon verfügbar.") }
            return
        }
        wandler = AVAudioConverter(from: eingang, to: zielFormat)
        wandler?.downmix = true
        ein.installTap(onBus: 0, bufferSize: 1024, format: eingang) { [weak self] puffer, _ in
            self?.mikrofon(puffer)
        }
        engine.prepare()
        do {
            try engine.start()
            stimme.play()
            audioLaeuft = true
            if zustand != .aktiv { Task { @MainActor in self.freizeichenStarten() } }
        } catch {
            Task { @MainActor in self.beenden(grund: "Audio konnte nicht starten: \(error.localizedDescription)") }
        }
    }

    func audioStoppen() {
        guard audioLaeuft else { return }
        audioLaeuft = false
        engine.inputNode.removeTap(onBus: 0)
        stimme.stop(); freizeichen.stop()
        engine.stop()
    }

    private func mikrofon(_ puffer: AVAudioPCMBuffer) {
        guard let w = wandler, let s = socket else { return }
        let aktiv = zustand == .aktiv && !stumm
        // Pegel fürs Leuchten
        if let k = puffer.floatChannelData?[0] {
            var summe: Float = 0
            let n = Int(puffer.frameLength)
            for i in stride(from: 0, to: n, by: 4) { summe += k[i] * k[i] }
            let p = min(1, sqrt(summe / Float(max(1, n / 4))) * 8)
            Task { @MainActor in self.pegelDu = aktiv ? p : 0 }
        }
        guard aktiv else { return }
        let kap = AVAudioFrameCount(Double(puffer.frameLength) * zielFormat.sampleRate / puffer.format.sampleRate) + 32
        guard let aus = AVAudioPCMBuffer(pcmFormat: zielFormat, frameCapacity: kap) else { return }
        var geliefert = false
        var fehler: NSError?
        w.convert(to: aus, error: &fehler) { _, status in
            if geliefert { status.pointee = .noDataNow; return nil }
            geliefert = true
            status.pointee = .haveData
            return puffer
        }
        guard fehler == nil, aus.frameLength > 0, let z = aus.int16ChannelData?[0] else { return }
        let daten = Data(bytes: z, count: Int(aus.frameLength) * 2)
        s.send(.data(daten)) { _ in }
    }

    @MainActor
    private func stimmFormatSetzen(_ sr: Double) {
        guard sr > 0, stimmFormat?.sampleRate != sr, let f = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1) else { return }
        stimmFormat = f
        if audioLaeuft {
            stimme.stop()
            engine.disconnectNodeOutput(stimme)
            engine.connect(stimme, to: engine.mainMixerNode, format: f)
            stimme.play()
        }
    }

    private func stimmeAbspielen(_ d: Data) {
        guard audioLaeuft, let f = stimmFormat else { return }
        let n = d.count / 2
        guard n > 0, let p = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(n)),
              let k = p.floatChannelData?[0] else { return }
        p.frameLength = AVAudioFrameCount(n)
        var summe: Float = 0
        d.withUnsafeBytes { (roh: UnsafeRawBufferPointer) in
            let werte = roh.bindMemory(to: Int16.self)
            for i in 0..<n {
                let x = Float(Int16(littleEndian: werte[i])) / 32768
                k[i] = x
                summe += x * x
            }
        }
        let pegel = min(1, sqrt(summe / Float(n)) * 6)
        Task { @MainActor in self.pegelSie = pegel }
        stimme.scheduleBuffer(p, completionHandler: { [weak self] in
            Task { @MainActor in if let self, !self.stimme.isPlaying { self.pegelSie = 0 } }
        })
        if !stimme.isPlaying { stimme.play() }
    }

    /// Deutsches Freizeichen: 425 Hz, 1 s Ton, 4 s Pause – solange es klingelt.
    @MainActor
    private func freizeichenStarten() {
        guard audioLaeuft, !eingehend, !freizeichen.isPlaying, zustand == .klingelt || zustand == .waehlt else { return }
        let f = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let n = AVAudioFrameCount(44100 * 5)
        guard let p = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: n), let k = p.floatChannelData?[0] else { return }
        p.frameLength = n
        for i in 0..<Int(n) {
            if i < 44100 {
                let huelle = min(1, Float(min(i, 44100 - i)) / 400)
                k[i] = sin(2 * .pi * 425 * Float(i) / 44100) * 0.18 * huelle
            } else { k[i] = 0 }
        }
        freizeichen.scheduleBuffer(p, at: nil, options: .loops, completionHandler: nil)
        freizeichen.play()
    }
}
