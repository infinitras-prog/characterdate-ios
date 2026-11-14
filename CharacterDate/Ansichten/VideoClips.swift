import AVFoundation
import SwiftUI

/// Videoanruf mit echten Bewegungen (iPhone): kurze Wan-Clips, die alle mit dem Szenenbild beginnen und enden – so
/// lassen sie sich nahtlos aneinanderhängen. Je nach Situation läuft der passende: sie redet (Clip mit Lippenbewegung),
/// du redest (zuhören/nicken), sie lacht, sonst ruhig mit gelegentlichen kleinen Gesten.
@Observable
final class ClipSpieler {
    var bereit = false
    @ObservationIgnored let spieler = AVQueuePlayer()
    @ObservationIgnored private var dateien: [String: [URL]] = [:]
    @ObservationIgnored private var letzteDatei: URL?
    @ObservationIgnored var sieRedet: () -> Bool = { false }
    @ObservationIgnored var duRedest: () -> Bool = { false }
    @ObservationIgnored var lachenBis = Date.distantPast
    @ObservationIgnored private var letzter = "ruhe"
    @ObservationIgnored private var beobachter: NSObjectProtocol?

    @MainActor
    func laden(_ v: Verbindung, clips: [String: [String]]) async {
        for (name, urls) in clips {
            for url in urls {
                guard let d = try? await v.medien(url) else { continue }
                let datei = FileManager.default.temporaryDirectory.appendingPathComponent("anrufclip_\(abs(url.hashValue)).mp4")
                try? d.write(to: datei)
                dateien[name, default: []].append(datei)
            }
        }
        guard !(dateien["ruhe"] ?? []).isEmpty else { return }
        spieler.isMuted = true
        spieler.actionAtItemEnd = .advance
        anhaengen(); anhaengen()
        beobachter = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            self?.anhaengen()
        }
        spieler.play()
        bereit = true
    }

    /// Nächsten Clip anhängen – zur aktuellen Lage passend (es liegen immer ~2 in der Schlange → keine Lücke).
    private func anhaengen() {
        let hat = { (n: String) in !(self.dateien[n] ?? []).isEmpty }
        var name = "ruhe"
        if Date() < lachenBis, hat("lachen") { name = "lachen"; lachenBis = .distantPast }
        else if sieRedet(), hat("reden") { name = "reden" }
        else if duRedest() { name = hat("nicken") && Double.random(in: 0...1) < 0.45 ? "nicken" : "ruhe" }
        else {
            let r = Double.random(in: 0...1)
            for (n, p) in [("laecheln", 0.12), ("nachdenken", 0.08), ("haare", 0.06)] where hat(n) && n != letzter && r < p { name = n; break }
        }
        letzter = name
        // Variante zufällig, nie dieselbe Datei zweimal hintereinander; Tempo leicht verschieden
        var liste = dateien[name] ?? dateien["ruhe"] ?? []
        if liste.count > 1 { liste.removeAll { $0 == letzteDatei } }
        guard let u = liste.randomElement() else { return }
        letzteDatei = u
        let item = AVPlayerItem(url: u)
        item.audioTimePitchAlgorithm = .timeDomain
        spieler.insert(item, after: nil)
        spieler.rate = Float.random(in: 0.92...1.08)
    }

    func stoppen() {
        spieler.pause(); spieler.removeAllItems()
        if let b = beobachter { NotificationCenter.default.removeObserver(b) }
    }
}

struct ClipAnsicht: UIViewRepresentable {
    let spieler: AVQueuePlayer
    func makeUIView(context: Context) -> Ebene {
        let v = Ebene(); v.ebene.player = spieler; v.ebene.videoGravity = .resizeAspectFill; return v
    }
    func updateUIView(_ v: Ebene, context: Context) {}
    final class Ebene: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var ebene: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
