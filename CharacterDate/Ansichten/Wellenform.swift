import SwiftUI

/// Wellenform-Leiste im Anruf: läuft von rechts nach links, Mint = du sprichst, Rosa = sie spricht.
@MainActor
@Observable
final class Wellenform {
    struct Wert { var pegel: Float; var sie: Bool }
    private(set) var werte: [Wert] = Array(repeating: Wert(pegel: 0, sie: false), count: 48)
    @ObservationIgnored private var uhr: Timer?

    func starten(_ t: Telefon) {
        uhr?.invalidate()
        uhr = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self, weak t] _ in
            MainActor.assumeIsolated {
                guard let self, let t else { return }
                let du = t.zustand == .aktiv ? t.pegelDu : 0
                let sie = t.pegelSie
                var w = self.werte
                w.removeFirst()
                w.append(sie >= du ? Wert(pegel: sie, sie: true) : Wert(pegel: du, sie: false))
                self.werte = w
            }
        }
    }

    func stoppen() { uhr?.invalidate(); uhr = nil }
}

struct WellenLeiste: View {
    let welle: Wellenform
    var hoehe: CGFloat = 44

    var body: some View {
        HStack(spacing: 10) {
            Text("Du").font(.caption2.bold()).foregroundStyle(Farbe.mint.opacity(aktivDu ? 1 : 0.45))
            Canvas { k, groesse in
                let n = welle.werte.count
                let breite = groesse.width / CGFloat(n)
                for (i, w) in welle.werte.enumerated() {
                    let h = max(3, CGFloat(min(1, w.pegel * 1.4)) * groesse.height)
                    let r = CGRect(x: CGFloat(i) * breite + breite * 0.2, y: (groesse.height - h) / 2,
                                   width: breite * 0.6, height: h)
                    let farbe: Color = w.pegel < 0.03 ? .white.opacity(0.25) : (w.sie ? Farbe.rose : Farbe.mint)
                    k.fill(Path(roundedRect: r, cornerRadius: breite * 0.3), with: .color(farbe))
                }
            }
            .frame(height: hoehe)
            Text("Sie").font(.caption2.bold()).foregroundStyle(Farbe.rose.opacity(aktivSie ? 1 : 0.45))
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.black.opacity(0.28), in: Capsule())
        .accessibilityHidden(true)
    }

    private var aktivDu: Bool { (welle.werte.last.map { !$0.sie && $0.pegel > 0.05 }) ?? false }
    private var aktivSie: Bool { (welle.werte.last.map { $0.sie && $0.pegel > 0.05 }) ?? false }
}
