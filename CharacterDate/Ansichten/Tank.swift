import SwiftUI

// MARK: - Tank-Stand

struct TankStatus: Decodable, Equatable {
    struct Manuell: Decodable, Equatable { var an: Bool = false; var pausiert: Bool = false; var fertig: Int = 0; var ziel: Int? = nil }
    var imTank: Int = 0
    var ziel: Int = 50
    var erzeugtGerade: Bool = false
    var schritt: String? = nil
    var voll: Bool? = nil
    var manuell: Manuell? = nil
    var superLikesUebrig: Int = 0

    var anteil: Double { min(1, Double(imTank) / Double(max(1, ziel))) }
    var fuellt: Bool { erzeugtGerade || (manuell?.an == true && manuell?.pausiert == false) }
    var pausiert: Bool { manuell?.an == true && manuell?.pausiert == true }
    var istVoll: Bool { voll ?? (imTank >= ziel) }
}

@MainActor
@Observable
final class TankModell {
    var stand: TankStatus?
    private var uhr: Task<Void, Never>?

    func starten(_ v: Verbindung) {
        uhr?.cancel()
        uhr = Task { [weak self] in
            while !Task.isCancelled {
                await self?.laden(v)
                let schnell = self?.stand?.fuellt == true || self?.stand?.manuell?.an == true
                try? await Task.sleep(for: .seconds(schnell ? 2.5 : 6))
            }
        }
    }

    func stoppen() { uhr?.cancel() }

    func laden(_ v: Verbindung) async {
        if let s: TankStatus = try? await v.anfrage("/api/tank/status") { stand = s }
    }

    func fuellen(_ aktion: String, _ v: Verbindung, menge: Int? = nil) async {
        struct A: Encodable { let aktion: String; let menge: Int? }
        if let s: TankStatus = try? await v.anfrage("/api/tank/fuellen", methode: "POST", body: A(aktion: aktion, menge: menge)) {
            withAnimation(.spring) { stand = s }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

// MARK: - Gläsernes Herz

struct HerzForm: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x / 100 * w, y: r.minY + y / 94 * h) }
        p.move(to: pt(50, 88))
        p.addCurve(to: pt(4, 31), control1: pt(20, 68), control2: pt(4, 50))
        p.addCurve(to: pt(28, 6), control1: pt(4, 16), control2: pt(15, 6))
        p.addCurve(to: pt(50, 20), control1: pt(38, 6), control2: pt(46, 12))
        p.addCurve(to: pt(72, 6), control1: pt(54, 12), control2: pt(62, 6))
        p.addCurve(to: pt(96, 31), control1: pt(85, 6), control2: pt(96, 16))
        p.addCurve(to: pt(50, 88), control1: pt(96, 50), control2: pt(80, 68))
        p.closeSubpath()
        return p
    }
}

private struct Welle: Shape {
    var hoehe: CGFloat         // Füllhöhe 0…1
    var phase: CGFloat
    var amplitude: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(hoehe, phase) }
        set { hoehe = newValue.first; phase = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Herz reicht von y 6 bis 88 (von 94)
        let oben = r.height * (88 - hoehe * 82) / 94
        p.move(to: CGPoint(x: 0, y: oben))
        var x: CGFloat = 0
        while x <= r.width {
            p.addLine(to: CGPoint(x: x, y: oben + sin(x / r.width * .pi * 3 + phase) * amplitude))
            x += 2
        }
        p.addLine(to: CGPoint(x: r.width, y: r.height))
        p.addLine(to: CGPoint(x: 0, y: r.height))
        p.closeSubpath()
        return p
    }
}

/// Der Tank als gläsernes Herz: Füllung mit Wellen, aufsteigende Herzchen beim Füllen, Glanz, Lämpchen.
struct TankHerz: View {
    let stand: TankStatus?
    var groesse: CGFloat = 170
    var lampen = true

    var body: some View {
        let s = stand
        VStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(s?.fuellt ?? false) && (s?.anteil ?? 0) == 0)) { t in
                let zeit = t.date.timeIntervalSinceReferenceDate
                let tempo = (s?.fuellt ?? false) ? 2.4 : 1.1
                ZStack {
                    HerzForm().fill(.white.opacity(0.05))
                    ZStack {
                        Welle(hoehe: s?.anteil ?? 0, phase: CGFloat(zeit * tempo), amplitude: groesse * 0.018)
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.48, blue: 0.75), Farbe.rose, Farbe.violett],
                                                 startPoint: .top, endPoint: .bottom)).opacity(0.55)
                        Welle(hoehe: s?.anteil ?? 0, phase: CGFloat(-zeit * tempo * 0.8 + 1.7), amplitude: groesse * 0.025)
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.48, blue: 0.75), Farbe.rose, Farbe.violett],
                                                 startPoint: .top, endPoint: .bottom))
                        if s?.fuellt == true { Blasen(zeit: zeit) }
                    }
                    .animation(.spring(duration: 1.2, bounce: 0.35), value: s?.anteil)
                    .clipShape(HerzForm())
                    HerzForm().fill(RadialGradient(colors: [.white.opacity(0.28), .white.opacity(0.04), .clear],
                                                   center: UnitPoint(x: 0.35, y: 0.25), startRadius: 0, endRadius: groesse * 0.6))
                    HerzForm().stroke(.white.opacity(0.35), lineWidth: 1.6)
                    if groesse > 60 {
                        VStack(spacing: 0) {
                            Text("\(s?.imTank ?? 0)").font(.system(size: groesse * 0.13, weight: .bold, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText())
                            Text("von \(s?.ziel ?? 0)").font(.system(size: groesse * 0.055, weight: .medium))
                        }
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 3)
                        .offset(y: -groesse * 0.06)
                    }
                }
                .frame(width: groesse, height: groesse * 0.94)
                .shadow(color: (s?.istVoll ?? false) ? Farbe.mint.opacity(0.5) : Farbe.rose.opacity(0.3), radius: groesse * 0.1)
            }
            if lampen, let s {
                HStack(spacing: 16) {
                    Lampe(farbe: Color(red: 0.96, green: 0.72, blue: 0.38), an: s.fuellt, blinkt: s.pausiert,
                          text: s.pausiert ? "Pausiert" : "Füllt")
                    Lampe(farbe: Farbe.mint, an: s.istVoll, blinkt: false, text: "Voll")
                }
                if s.fuellt, let sch = s.schritt, !sch.isEmpty {
                    Text(sch).font(.caption2).foregroundStyle(Farbe.text3).multilineTextAlignment(.center)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tank: \(s?.imTank ?? 0) von \(s?.ziel ?? 0) Profilen" + ((s?.istVoll ?? false) ? ", voll" : (s?.fuellt ?? false) ? ", wird gefüllt" : ""))
    }

    private struct Blasen: View {
        let zeit: Double
        var body: some View {
            Canvas { ctx, size in
                for i in 0..<9 {
                    let dauer = 2.6 + Double(i % 4) * 0.5
                    let ph = ((zeit + Double(i) * 0.53).truncatingRemainder(dividingBy: dauer)) / dauer
                    let x = size.width * (0.14 + Double((i * 37) % 72) / 100) + sin(ph * .pi * 2) * 3
                    let y = size.height * (0.98 - ph * 0.8)
                    var c = ctx
                    c.opacity = ph < 0.15 ? ph / 0.15 * 0.85 : (1 - ph) * 0.85
                    var bild = c.resolve(Image(systemName: "heart.fill"))
                    bild.shading = .color(.white)
                    let g = size.width * 0.05 * (0.6 + ph * 0.5)
                    c.draw(bild, in: CGRect(x: x - g / 2, y: y - g / 2, width: g, height: g))
                }
            }
        }
    }
}

struct Lampe: View {
    let farbe: Color
    let an: Bool
    let blinkt: Bool
    let text: String
    @State private var puls = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(an || blinkt ? AnyShapeStyle(RadialGradient(colors: [.white, farbe, farbe.opacity(0.7)], center: UnitPoint(x: 0.35, y: 0.35),
                                                                 startRadius: 0, endRadius: 7)) : AnyShapeStyle(Color(red: 0.23, green: 0.2, blue: 0.28)))
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                .shadow(color: an ? farbe.opacity(puls ? 0.5 : 0.95) : .clear, radius: an ? (puls ? 4 : 10) : 0)
                .opacity(blinkt ? (puls ? 0.25 : 1) : 1)
            if !text.isEmpty { Text(text).font(.caption).foregroundStyle(an ? .white : Farbe.text2) }
        }
        .onAppear { withAnimation(.easeInOut(duration: blinkt ? 0.8 : 1.2).repeatForever(autoreverses: true)) { puls = true } }
    }
}

/// Großer Tank mit Steuerung (Swipe-Blatt und Einstellungen).
struct TankKarte: View {
    @Environment(Verbindung.self) private var v
    @State private var modell = TankModell()
    @State private var menge = 10

    var body: some View {
        VStack(spacing: 14) {
            TankHerz(stand: modell.stand)
            if modell.stand?.manuell?.an != true {
                Picker("Wie viele?", selection: $menge) {
                    ForEach([3, 5, 10, 20, 30], id: \.self) { Text("\($0)").tag($0) }
                }.pickerStyle(.segmented)
            }
            HStack(spacing: 10) {
                if let s = modell.stand {
                    let m = s.manuell
                    if m?.an != true {
                        Button { Task { await modell.fuellen("start", v, menge: menge) } } label: {
                            Label("\(menge) Profile erzeugen", systemImage: "bolt.fill")
                        }.buttonStyle(HauptKnopf())
                    } else {
                        if m?.pausiert == true {
                            Button { Task { await modell.fuellen("weiter", v) } } label: { Label("Weiter", systemImage: "play.fill") }
                                .buttonStyle(HauptKnopf())
                        } else {
                            Button { Task { await modell.fuellen("pause", v) } } label: { Label("Pause", systemImage: "pause.fill") }
                                .buttonStyle(.bordered).tint(.white)
                        }
                        Button(role: .destructive) { Task { await modell.fuellen("stopp", v) } } label: {
                            Label("Abbrechen", systemImage: "stop.fill")
                        }.buttonStyle(.bordered)
                    }
                }
            }
            if let m = modell.stand?.manuell, m.an {
                Text("\(m.fertig) von \(m.ziel ?? menge) neuen Profilen · fertige bleiben, auch wenn du abbrichst")
                    .font(.caption2).foregroundStyle(Farbe.text3).multilineTextAlignment(.center)
            } else {
                Text("Von selbst füllt er sich nur, wenn dein PC frei ist. »Jetzt füllen« läuft auch, während du aktiv bist.")
                    .font(.caption2).foregroundStyle(Farbe.text3).multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .onAppear { modell.starten(v) }
        .onDisappear { modell.stoppen() }
    }
}
