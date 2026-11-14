import SwiftUI
import SpriteKit
import Vision

/// Lebendiges Porträt für den Videoanruf (wie am PC): Apple Vision findet Mund und Augen im Profilbild, ein
/// verformbares Bildgitter (SpriteKit-Warp) öffnet den Mund im Takt ihrer Stimme, lässt die Augen blinzeln und den
/// Kopf leicht wiegen. Läuft komplett auf dem iPhone, ohne zusätzliche Rechenlast für den PC.
struct LebendigesPortraet: UIViewRepresentable {
    let bild: UIImage
    let pegel: () -> Float          // Stimmpegel 0…1 (aus dem Telefon)
    let aktiv: Bool

    func makeUIView(context: Context) -> SKView {
        let v = SKView()
        v.allowsTransparency = true
        v.backgroundColor = .clear
        v.preferredFramesPerSecond = 60
        let szene = PortraetSzene(bild: bild)
        szene.pegel = pegel
        szene.scaleMode = .resizeFill
        v.presentScene(szene)
        context.coordinator.szene = szene
        return v
    }

    func updateUIView(_ v: SKView, context: Context) {
        context.coordinator.szene?.aktiv = aktiv
        context.coordinator.szene?.pegel = pegel
    }

    func makeCoordinator() -> Koordinator { Koordinator() }
    final class Koordinator { var szene: PortraetSzene? }
}

final class PortraetSzene: SKScene {
    private let bild: UIImage
    private let figur: SKSpriteNode
    private let spalten = 28, zeilen = 28
    var pegel: () -> Float = { 0 }
    var aktiv = false

    // Gesichtsmerkmale in Bildkoordinaten (0…1, Ursprung unten links wie SpriteKit)
    private var mund = CGPoint(x: 0.5, y: 0.4), mundBreite: CGFloat = 0.1
    private var augen: [(oben: CGFloat, unten: CGFloat, x: CGFloat, breite: CGFloat)] = []
    private var gesicht = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
    private var gefunden = false
    private var offen: CGFloat = 0
    private var naechsterBlinzler: TimeInterval = 2, blinzelStart: TimeInterval = -1
    private var start: TimeInterval = -1

    init(bild: UIImage) {
        self.bild = bild
        figur = SKSpriteNode(texture: SKTexture(image: bild))
        super.init(size: CGSize(width: 400, height: 800))
        backgroundColor = .clear
        addChild(figur)
        gesichtFinden()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func gesichtFinden() {
        guard let cg = bild.cgImage else { return }
        let anfrage = VNDetectFaceLandmarksRequest { [weak self] r, _ in
            guard let self, let f = (r.results as? [VNFaceObservation])?.first, let lm = f.landmarks else { return }
            let box = f.boundingBox   // normiert, Ursprung unten links
            func punkte(_ reg: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                (reg?.normalizedPoints ?? []).map { CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height) }
            }
            let lippen = punkte(lm.innerLips).isEmpty ? punkte(lm.outerLips) : punkte(lm.innerLips)
            let aussen = punkte(lm.outerLips)
            DispatchQueue.main.async {
                self.gesicht = box
                if !lippen.isEmpty {
                    self.mund = CGPoint(x: lippen.map(\.x).reduce(0, +) / CGFloat(lippen.count),
                                        y: lippen.map(\.y).reduce(0, +) / CGFloat(lippen.count))
                    let xs = (aussen.isEmpty ? lippen : aussen).map(\.x)
                    self.mundBreite = (xs.max() ?? 0.55) - (xs.min() ?? 0.45)
                }
                for auge in [punkte(lm.leftEye), punkte(lm.rightEye)] where !auge.isEmpty {
                    let ys = auge.map(\.y), xs = auge.map(\.x)
                    self.augen.append((oben: ys.max()!, unten: ys.min()!, x: xs.reduce(0, +) / CGFloat(xs.count),
                                       breite: (xs.max()! - xs.min()!)))
                }
                self.gefunden = true
            }
        }
        let h = VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(bild.imageOrientation))
        DispatchQueue.global(qos: .userInitiated).async { try? h.perform([anfrage]) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0 else { return }
        // »cover«: Bild füllt den Bildschirm, Gesicht im oberen Drittel
        let s = max(size.width / bild.size.width, size.height / bild.size.height) * 1.04
        figur.size = CGSize(width: bild.size.width * s, height: bild.size.height * s)
        figur.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    override func update(_ zeit: TimeInterval) {
        if start < 0 { start = zeit }
        let t = zeit - start
        // Gesicht nach oben schieben (Ansicht wie im Videoanruf)
        if gefunden {
            let zielY = size.height * 0.58 - (gesicht.midY - 0.5) * figur.size.height
            figur.position.y += (min(figur.size.height / 2, max(size.height - figur.size.height / 2, zielY)) - figur.position.y) * 0.1
            figur.position.x = size.width / 2 - (gesicht.midX - 0.5) * figur.size.width
        }
        let ziel = aktiv ? CGFloat(min(1, pegel() * 1.1)) : 0
        offen += (ziel - offen) * (ziel > offen ? 0.55 : 0.25)
        if t > naechsterBlinzler { blinzelStart = t; naechsterBlinzler = t + 2 + Double.random(in: 0...4) }
        let bz = (t - blinzelStart) / 0.16
        let lid: CGFloat = (bz >= 0 && bz < 1) ? CGFloat(sin(bz * .pi)) : 0
        let winkel = CGFloat((sin(t * 0.55) * 1.3 + sin(t * 1.3) * 0.4) * .pi / 180)
        let nick = CGFloat(sin(t * 2.1)) * offen * mundBreite * 0.04 + CGFloat(sin(t * 0.8)) * mundBreite * 0.02
        let oeffnung = offen * mundBreite * 0.2
        let kinnY = gesicht.minY, mitteX = gesicht.midX
        let gr = max(gesicht.width, gesicht.height) * 0.6

        var quelle: [SIMD2<Float>] = [], ziel2: [SIMD2<Float>] = []
        for j in 0...zeilen {
            for i in 0...spalten {
                let u = CGFloat(i) / CGFloat(spalten), v = CGFloat(j) / CGFloat(zeilen)
                quelle.append(SIMD2(Float(u), Float(v)))
                guard gefunden, i > 0, i < spalten, j > 0, j < zeilen else { ziel2.append(SIMD2(Float(u), Float(v))); continue }
                var x = u, y = v
                let kg = max(0, min(1, 1.6 - hypot(u - gesicht.midX, v - gesicht.midY) / gr))
                if kg > 0 {
                    // Mund: unterhalb der Mundmitte nach unten (Kinn mit), oberhalb leicht hoch
                    let d = hypot((u - mund.x) / (mundBreite * 1.3), (v - mund.y) / (mundBreite * 1.1))
                    let mg = exp(-d * d)
                    if v < mund.y {
                        let kinnAnteil = max(0, min(1, (mund.y - v) / max(0.01, mund.y - kinnY)))
                        y -= oeffnung * (mg + 0.55 * kinnAnteil * (1 - mg)) * (v > kinnY - 0.02 ? 1 : 0.4)
                    } else {
                        y += oeffnung * 0.15 * mg
                    }
                    // Blinzeln: Oberlid-Bereich wandert zum Unterlid
                    for a in augen {
                        let dx = abs(u - a.x) / (a.breite * 0.75)
                        if dx < 1, v <= a.oben + (a.oben - a.unten) * 0.6, v >= a.unten {
                            let anteil = (v - a.unten) / max(0.001, (a.oben - a.unten) * 1.6)
                            y -= lid * (a.oben - a.unten) * 0.9 * min(1, anteil) * (1 - dx)
                        }
                    }
                    // Kopf wiegt um den Hals
                    let px = x - mitteX, py = y - (kinnY - gr * 0.4)
                    let w = winkel * kg
                    x = mitteX + px * cos(w) - py * sin(w)
                    y = kinnY - gr * 0.4 + px * sin(w) + py * cos(w)
                    y -= nick * kg
                }
                ziel2.append(SIMD2(Float(x), Float(y)))
            }
        }
        figur.warpGeometry = SKWarpGeometryGrid(columns: spalten, rows: zeilen, sourcePositions: quelle, destinationPositions: ziel2)
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
