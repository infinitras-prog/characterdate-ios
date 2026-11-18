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
    /// Freizeichen über einen eigenen Player – nicht durch die Sprachverarbeitung (Echo-/Rauschfilter schluckten den Ton)
    private var freizeichen: AVAudioPlayer?
    private var stimmFormat: AVAudioFormat?
    private let zielFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var audioLaeuft = false
    /// Darf das Mikrofon gerade senden? (vom Audio-Thread gelesen – nicht das @Observable-Feld »zustand« dort lesen)
    @ObservationIgnored private var sendenErlaubt = false
    @ObservationIgnored private var mikroPakete = 0
    @ObservationIgnored private var mikroSpitze: Float = 0
    @ObservationIgnored private var mikroRest: [Float] = []
    @ObservationIgnored private var mikroPos: Double = 0
    @ObservationIgnored private var konfigBeobachter: NSObjectProtocol?
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
        // Mikrofon-Erlaubnis ausdrücklich holen – ohne sie liefert iOS nur Stille (Anruf läuft, aber sie hört nichts)
        AVAudioApplication.requestRecordPermission { [weak self] ok in
            guard let self, !ok else { return }
            Task { @MainActor in
                self.info = "Kein Zugriff aufs Mikrofon – in den iPhone-Einstellungen › CharacterDate › Mikrofon erlauben."
                self.melden("Mikrofon-Erlaubnis verweigert")
            }
        }
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
        sendenErlaubt = zustand == .aktiv && !an
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
            melden("Anruf endet: Zustand \(zustand), Grund \(g ?? "–"), nach \(dauer) s, Mikro-Pakete \(mikroPakete), "
                   + "Spitze \(String(format: "%.3f", mikroSpitze)), letzter Fehler \(letzterFehler ?? "–")")
        }
        sendenErlaubt = false
        if zustand != .beendet {
            senden(["typ": "auflegen"])
            zustand = .beendet
        }
        let s = socket
        socket = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { s?.cancel(with: .normalClosure, reason: nil) }
        freizeichenStoppen()
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
                freizeichenStoppen()
                info = nil
                zustand = .aktiv
                start = Date()
                sendenErlaubt = !stumm
                // Nach dem Freizeichen kann iOS die Audio-Einheit umgebaut haben → Aufnahme nach 4 s prüfen
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    guard let self, self.zustand == .aktiv else { return }
                    let laeuft = self.engine.isRunning
                    self.melden("Mikro nach 4 s: \(self.mikroPakete) Pakete, Spitze \(String(format: "%.3f", self.mikroSpitze)), "
                                + "Engine läuft: \(laeuft), Eingang \(self.engine.inputNode.outputFormat(forBus: 0))")
                    if !laeuft || self.mikroPakete == 0 { self.audioNeustarten("kein Mikrofonton nach 4 s") }
                }
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
            pufferSperre.lock(); ausstehend = 0; pufferSperre.unlock()
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
        let sf = stimmFormat ?? AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        stimmFormat = sf
        engine.connect(stimme, to: engine.mainMixerNode, format: sf)

        let eingang = ein.outputFormat(forBus: 0)
        guard eingang.sampleRate > 0, eingang.channelCount > 0 else {
            Task { @MainActor in self.beenden(grund: "Kein Mikrofon verfügbar.") }
            return
        }
        ein.installTap(onBus: 0, bufferSize: 1024, format: eingang) { [weak self] puffer, _ in
            self?.mikrofon(puffer)
        }
        if konfigBeobachter == nil {
            // iOS baut die Audio-Einheit um (Freizeichen, Lautsprecher, Kopfhörer) → die Engine stoppt still; neu starten
            konfigBeobachter = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                                       queue: .main) { [weak self] _ in
                self?.audioNeustarten("Audio-Konfiguration geändert")
            }
        }
        engine.prepare()
        do {
            try engine.start()
            stimme.play()
            audioLaeuft = true

        } catch {
            Task { @MainActor in self.beenden(grund: "Audio konnte nicht starten: \(error.localizedDescription)") }
        }
    }

    func audioNeustarten(_ grund: String) {
        guard zustand != .beendet else { return }
        melden("Audio neu gestartet: \(grund)")
        if audioLaeuft {
            audioLaeuft = false
            engine.inputNode.removeTap(onBus: 0)
            stimme.stop()
            engine.stop()
        }
        mikroRest = []
        mikroPos = 0
        audioStarten()
    }

    func audioStoppen() {
        if let b = konfigBeobachter { NotificationCenter.default.removeObserver(b); konfigBeobachter = nil }
        guard audioLaeuft else { return }
        audioLaeuft = false
        engine.inputNode.removeTap(onBus: 0)
        stimme.stop(); freizeichenStoppen()
        engine.stop()
    }

    /// Mikrofon → 16 kHz PCM16 mono, selbst heruntergerechnet (Mittelwert je Fenster, wie am PC). Kein AVAudioConverter:
    /// der lieferte mit Sprachverarbeitung auf manchen iPhones nur Nullen.
    private func mikrofon(_ puffer: AVAudioPCMBuffer) {
        guard let s = socket else { return }
        let n = Int(puffer.frameLength)
        guard n > 0 else { return }
        var mono = [Float](repeating: 0, count: n)
        if let k = puffer.floatChannelData {
            let kanaele = Int(puffer.format.channelCount)
            for c in 0..<max(1, min(kanaele, 2)) { for i in 0..<n { mono[i] += k[c][i] } }
            if kanaele >= 2 { for i in 0..<n { mono[i] *= 0.5 } }
        } else if let k = puffer.int16ChannelData {
            for i in 0..<n { mono[i] = Float(k[0][i]) / 32768 }
        } else { return }
        // Pegel fürs Leuchten und für die Diagnose
        var summe: Float = 0
        for i in stride(from: 0, to: n, by: 4) { summe += mono[i] * mono[i] }
        let rms = sqrt(summe / Float(max(1, n / 4)))
        let aktiv = sendenErlaubt
        Task { @MainActor in self.pegelDu = aktiv ? min(1, rms * 8) : 0 }
        guard aktiv else { return }
        mikroSpitze = max(mikroSpitze, rms)
        // Herunterrechnen auf 16 kHz
        let verhaeltnis = puffer.format.sampleRate / 16000
        let daten = mikroRest + mono
        var aus = [Int16]()
        aus.reserveCapacity(Int(Double(daten.count) / verhaeltnis) + 2)
        var pos = mikroPos
        while Int(pos + verhaeltnis) <= daten.count {
            let a = Int(pos), b = max(a + 1, Int(pos + verhaeltnis))
            var w: Float = 0
            for i in a..<b { w += daten[i] }
            w /= Float(b - a)
            aus.append(Int16(max(-1, min(1, w)) * 32767))
            pos += verhaeltnis
        }
        let verbraucht = min(daten.count, Int(pos))
        mikroRest = Array(daten[verbraucht...])
        mikroPos = pos - Double(verbraucht)
        guard !aus.isEmpty else { return }
        mikroPakete += 1
        let bytes = aus.withUnsafeBufferPointer { Data(buffer: $0) }
        s.send(.data(bytes)) { [weak self] f in if let f { self?.letzterFehler = "Mikro senden: \(f.localizedDescription)" } }
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

    @ObservationIgnored private var ausstehend = 0
    @ObservationIgnored private let pufferSperre = NSLock()
    private func stueckFertig() { pufferSperre.lock(); ausstehend = max(0, ausstehend - 1); pufferSperre.unlock() }

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
        // Puffer gegen Stottern: ist die Warteschlange leer (Satzanfang oder leergelaufen), 140 ms Stille vorweg –
        // dann fallen kleine Verzögerungen beim Rechnen der nächsten Stücke nicht als Lücke auf
        pufferSperre.lock()
        let leer = ausstehend == 0
        ausstehend += leer ? 2 : 1
        pufferSperre.unlock()
        if leer, let still = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(f.sampleRate * 0.14)) {
            still.frameLength = still.frameCapacity          // mit Nullen gefüllt
            stimme.scheduleBuffer(still, completionHandler: { [weak self] in self?.stueckFertig() })
        }
        stimme.scheduleBuffer(p, completionHandler: { [weak self] in
            self?.stueckFertig()
            Task { @MainActor in if let self, !self.stimme.isPlaying { self.pegelSie = 0 } }
        })
        if !stimme.isPlaying { stimme.play() }
    }

    /// Deutsches Freizeichen: 425 Hz, 1 s Ton, 4 s Pause – solange gewählt wird / es klingelt.
    @MainActor
    private func freizeichenStarten() {
        guard !eingehend, freizeichen == nil, zustand == .klingelt || zustand == .waehlt else { return }
        let rate = 16000, n = rate * 5
        var pcm = [Int16](repeating: 0, count: n)
        for i in 0..<rate {
            let huelle = min(1.0, Double(min(i, rate - i)) / 160)
            pcm[i] = Int16(sin(2 * .pi * 425 * Double(i) / Double(rate)) * 0.5 * huelle * 32767)
        }
        var wav = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 2)) }
        wav.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 2)); wav.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        wav.append("data".data(using: .ascii)!); u32(UInt32(n * 2))
        pcm.withUnsafeBufferPointer { wav.append(Data(buffer: $0)) }
        guard let p = try? AVAudioPlayer(data: wav) else { melden("Freizeichen: Player ließ sich nicht anlegen"); return }
        p.numberOfLoops = -1
        p.volume = 1
        p.prepareToPlay()
        if !p.play() { melden("Freizeichen: Abspielen fehlgeschlagen") }
        freizeichen = p
    }

    private func freizeichenStoppen() {
        freizeichen?.stop()
        freizeichen = nil
    }
}
