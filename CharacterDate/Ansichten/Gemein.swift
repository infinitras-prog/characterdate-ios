import SwiftUI
import AVFoundation

/// Bild vom PC (Schlüssel im Header, Zwischenspeicher im Arbeitsspeicher).
struct NetzBild: View {
    @Environment(Verbindung.self) private var v
    let pfad: String?
    var modus: ContentMode = .fill
    @State private var bild: UIImage?
    @State private var fehler = false

    var body: some View {
        ZStack {
            if let bild {
                Image(uiImage: bild).resizable().aspectRatio(contentMode: modus)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                Rectangle().fill(Farbe.verlauf).opacity(fehler ? 0.35 : 0.6)
                if !fehler && pfad != nil { ProgressView().tint(.white) }
            }
        }
        .task(id: pfad) {
            guard let pfad, !pfad.isEmpty else { return }
            do {
                let d = try await v.medien(pfad)
                withAnimation(.easeOut(duration: 0.5)) { bild = UIImage(data: d) }
            } catch { fehler = true }
        }
    }
}

struct Avatar: View {
    let c: Charakter
    var groesse: CGFloat = 44
    var online = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let a = c.avatarUrl { NetzBild(pfad: a) }
                else { Farbe.verlauf.overlay(Text(String(c.name.prefix(1))).font(.system(size: groesse * 0.4, weight: .semibold))) }
            }
            .frame(width: groesse, height: groesse).clipShape(Circle())
            if online {
                Circle().fill(c.gerade.verfuegbar == "ja" ? Farbe.mint : c.gerade.verfuegbar == "kurz" ? .orange : .gray)
                    .frame(width: groesse * 0.26, height: groesse * 0.26)
                    .overlay(Circle().stroke(Farbe.grund, lineWidth: 2))
            }
        }
    }
}

/// Spielt Sprachnachrichten vom PC ab (WAV wird mit Schlüssel geladen, dann lokal gespielt).
@Observable
final class Abspieler {
    static let shared = Abspieler()
    var aktuell: String?
    var fortschritt: Double = 0
    private var spieler: AVAudioPlayer?
    private var uhr: Timer?

    @MainActor
    func umschalten(_ pfad: String, v: Verbindung) async {
        if aktuell == pfad { stopp(); return }
        stopp()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let d = try await v.medien(pfad)
            let p = try AVAudioPlayer(data: d)
            p.play()
            spieler = p; aktuell = pfad; fortschritt = 0
            uhr = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let s = self.spieler, s.duration > 0 else { return }
                if !s.isPlaying { self.stopp(); return }          // zu Ende gespielt
                self.fortschritt = s.currentTime / s.duration
            }
        } catch { stopp() }
    }

    func stopp() {
        spieler?.stop(); spieler = nil; aktuell = nil; fortschritt = 0
        uhr?.invalidate(); uhr = nil
    }
}

struct SprachBlase: View {
    @Environment(Verbindung.self) private var v
    let pfad: String
    let dauer: Double?
    var hell = false
    private var spieler: Abspieler { Abspieler.shared }
    private let balken: [CGFloat] = (0..<26).map { i in 0.3 + abs(sin(Double(i) * 1.7)) * 0.7 }

    var body: some View {
        let laeuft = spieler.aktuell == pfad
        HStack(spacing: 10) {
            Button {
                Task { await spieler.umschalten(pfad, v: v) }
            } label: {
                Image(systemName: laeuft ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(hell ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(Farbe.verlauf), in: Circle())
                    .foregroundStyle(.white)
            }
            HStack(spacing: 2) {
                ForEach(balken.indices, id: \.self) { i in
                    Capsule().frame(width: 3, height: 24 * balken[i])
                        .opacity(laeuft && Double(i) / Double(balken.count) <= spieler.fortschritt ? 1 : 0.45)
                }
            }
            if let dauer { Text(String(format: "%d:%02d", Int(dauer) / 60, Int(dauer) % 60)).font(.caption.monospacedDigit()).opacity(0.75) }
        }
    }
}

/// Mikrofon-Aufnahme für Sprachnachrichten (AAC/M4A).
@Observable
final class Rekorder {
    var laeuft = false
    var sekunden = 0
    private var rec: AVAudioRecorder?
    private var uhr: Timer?
    private var datei: URL { FileManager.default.temporaryDirectory.appendingPathComponent("sprachnachricht.m4a") }

    @MainActor
    func start() async throws {
        let erlaubt = await AVAudioApplication.requestRecordPermission()
        guard erlaubt else { throw Verbindung.Fehler.text("Kein Zugriff aufs Mikrofon. Erlaube ihn in den iOS-Einstellungen.") }
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try s.setActive(true)
        let r = try AVAudioRecorder(url: datei, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                                                          AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
        r.record()
        rec = r; laeuft = true; sekunden = 0
        uhr = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sekunden += 1 }
    }

    /// Beendet die Aufnahme; gibt die Datei zurück (nil = verworfen).
    func stopp(verwerfen: Bool = false) -> Data? {
        rec?.stop(); laeuft = false; uhr?.invalidate()
        defer { rec = nil }
        if verwerfen { return nil }
        return try? Data(contentsOf: datei)
    }
}
