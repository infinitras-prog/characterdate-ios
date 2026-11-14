import SwiftUI
import AVFoundation

/// Stummes Video aus dem App-Paket in Endlosschleife (für den Startbildschirm).
struct SchleifenVideo: UIViewRepresentable {
    let name: String

    final class Ansicht: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var spielerEbene: AVPlayerLayer { layer as! AVPlayerLayer }
        var schleife: AVPlayerLooper?
    }

    func makeUIView(context: Context) -> Ansicht {
        let v = Ansicht()
        v.backgroundColor = .clear
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else { return v }
        let eintrag = AVPlayerItem(url: url)
        let spieler = AVQueuePlayer()
        spieler.isMuted = true
        v.schleife = AVPlayerLooper(player: spieler, templateItem: eintrag)
        v.spielerEbene.player = spieler
        v.spielerEbene.videoGravity = .resizeAspectFill
        spieler.play()
        return v
    }

    func updateUIView(_ uiView: Ansicht, context: Context) {}
}
