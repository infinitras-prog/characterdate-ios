import SwiftUI
import CoreHaptics

/// Startbildschirm ohne Video – identisch zum Windows-Splash (gleicher Zeitplan, Bild im 9:16-Format):
/// Herz taucht auf, Herzschlag-Glut, drehende Strahlen, Partikelring, Funken; bei 3,9 s Blitz + Druckwelle + Name.
struct Splash: View {
    let fertig: () -> Void
    @State private var start = Date()
    @State private var weg = false
    @State private var name = false
    @State private var schimmer = false
    @Environment(\.accessibilityReduceMotion) private var ruhig
    private let zuendung = 3.9
    private let szene = SplashSzene()
    private let bernstein = Color(red: 0.96, green: 0.72, blue: 0.38)

    var body: some View {
        TimelineView(.animation(paused: ruhig)) { zeit in
            let t = ruhig ? 5.0 : zeit.date.timeIntervalSince(start)
            GeometryReader { g in
                ZStack {
                    Farbe.grund
                    Image("SplashHoch").resizable().scaledToFill()
                        .frame(width: g.size.width, height: g.size.height).clipped()
                        .brightness(SplashSzene.helligkeit(t))
                        .blur(radius: SplashSzene.unschaerfe(t))
                        .scaleEffect(SplashSzene.kamera(t), anchor: UnitPoint(x: 0.5, y: 0.41))
                    Canvas { ctx, groesse in szene.zeichnen(ctx, groesse, t, zuendung: zuendung) }
                        .blendMode(.screen)
                    LinearGradient(colors: [.clear, Farbe.grund.opacity(0.9)], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("Character").foregroundStyle(.white)
                    Text("Date").foregroundStyle(Farbe.verlauf)
                        .overlay(
                            LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 60).offset(x: schimmer ? 90 : -90).blendMode(.overlay)
                                .mask(Text("Date"))
                        )
                    Text("AI").font(.system(size: 14, weight: .semibold)).tracking(3).foregroundStyle(bernstein).padding(.leading, 6)
                }
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .shadow(color: Farbe.rose.opacity(0.5), radius: 18)
                .opacity(name ? 1 : 0).offset(y: name ? 0 : 18).blur(radius: name ? 0 : 10).scaleEffect(name ? 1 : 0.96)
                Text("Deine Begleitung erwacht …").font(.footnote).foregroundStyle(Farbe.text2)
                    .opacity(name ? 1 : 0).animation(.easeOut(duration: 0.8).delay(0.7), value: name)
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea()
        .opacity(weg ? 0 : 1)
        .scaleEffect(weg ? 1.08 : 1)
        .onAppear {
            start = Date()
            if !ruhig { Herzschlag.spielen() }
            DispatchQueue.main.asyncAfter(deadline: .now() + (ruhig ? 0.2 : zuendung)) {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { name = true }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false).delay(1.0)) { schimmer = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.8) {
                withAnimation(.easeInOut(duration: 0.8)) { weg = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { fertig() }
            }
        }
    }
}

/// Berechnet die ganze Splash-Szene aus der verstrichenen Zeit (keine Zustände je Bild → flüssig und deterministisch).
/// Drei Herzschläge als Haptik – genau im Takt des Leuchtens (Szene: Schlag ab 1,6 s, Periode 1,25 s,
/// Spitzen bei 12 % und 34 % der Periode). Jeder Schlag ist ein Doppelschlag: kräftig »Lub«, weicher »Dub«.
enum Herzschlag {
    private static var engine: CHHapticEngine?

    static func spielen() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return ersatz() }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true
            try e.start()
            var ereignisse: [CHHapticEvent] = []
            for k in 0..<3 {
                let basis = 1.6 + Double(k) * 1.25
                // Lub: tief und kräftig, mit kurzem Nachklang
                ereignisse.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    .init(parameterID: .hapticIntensity, value: 1.0), .init(parameterID: .hapticSharpness, value: 0.25)],
                    relativeTime: basis + 0.15))
                ereignisse.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.45), .init(parameterID: .hapticSharpness, value: 0.1)],
                    relativeTime: basis + 0.16, duration: 0.09))
                // Dub: weicher
                ereignisse.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.6), .init(parameterID: .hapticSharpness, value: 0.2)],
                    relativeTime: basis + 0.425))
            }
            let spieler = try e.makePlayer(with: CHHapticPattern(events: ereignisse, parameters: []))
            try spieler.start(atTime: CHHapticTimeImmediate)
            engine = e        // festhalten, bis die Schläge gespielt sind
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { engine?.stop(); engine = nil }
        } catch {
            ersatz()
        }
    }

    /// Geräte ohne Core Haptics: einfache Stöße im gleichen Takt
    private static func ersatz() {
        let stark = UIImpactFeedbackGenerator(style: .heavy), weich = UIImpactFeedbackGenerator(style: .soft)
        for k in 0..<3 {
            let basis = 1.6 + Double(k) * 1.25
            DispatchQueue.main.asyncAfter(deadline: .now() + basis + 0.15) { stark.impactOccurred(intensity: 1.0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + basis + 0.425) { weich.impactOccurred(intensity: 0.6) }
        }
    }
}

struct SplashSzene {
    struct Teil { let w: Double; let v: Double; let r: Double; let d: Double; let farbe: Color; let phase: Double }
    struct Funke { let x: Double; let tempo: Double; let r: Double; let versatz: Double; let leben: Double; let farbe: Color }
    struct Splitter { let winkel: Double; let tempo: Double; let r: Double; let leben: Double; let farbe: Color }
    static let farben: [Color] = [Color(red: 1, green: 0.886, blue: 0.69), Color(red: 0.937, green: 0.388, blue: 0.71),
                                   Color(red: 0.64, green: 0.42, blue: 0.98), .white]
    let ring: [Teil]
    let funken: [Funke]
    let splitter: [Splitter]

    init() {
        func f() -> Color { SplashSzene.farben[Int.random(in: 0..<4)] }
        ring = (0..<170).map { _ in
            Teil(w: .random(in: 0...6.283), v: .random(in: 0.24...0.6), r: .random(in: 0.5...2), d: .random(in: -0.03...0.03),
                 farbe: Bool.random() ? SplashSzene.farben[0] : f(), phase: .random(in: 0...6.283))
        }
        funken = (0..<70).map { _ in
            Funke(x: .random(in: 0...1), tempo: .random(in: 18...50), r: .random(in: 0.6...2.4), versatz: .random(in: 0...6),
                  leben: .random(in: 3.5...7), farbe: f())
        }
        splitter = (0..<140).map { _ in
            Splitter(winkel: .random(in: 0...6.283), tempo: .random(in: 90...330), r: .random(in: 0.7...2.6), leben: .random(in: 1...2.6), farbe: f())
        }
    }

    /// Doppelter Herzschlag, Periode 1,25 s (wie am PC).
    static func schlag(_ t: Double) -> Double {
        guard t > 1.6 else { return 0 }
        let p = (t - 1.6).truncatingRemainder(dividingBy: 1.25) / 1.25
        return exp(-pow((p - 0.12) / 0.05, 2)) + 0.6 * exp(-pow((p - 0.34) / 0.05, 2))
    }
    static func wach(_ t: Double) -> Double { min(1, t / 1.6) }
    static func helligkeit(_ t: Double) -> Double { -0.9 * (1 - wach(t)) + 0.12 * schlag(t) }
    static func unschaerfe(_ t: Double) -> Double { 14 * pow(1 - wach(t), 2) }
    static func kamera(_ t: Double) -> Double {
        if t < 6.5 { let k = t / 6.5; return 1 + 0.12 * (1 - pow(1 - k, 3)) }
        return 1.12 + 0.015 * (1 - cos((t - 6.5) * 1.8))
    }

    func zeichnen(_ ctx: GraphicsContext, _ g: CGSize, _ t: Double, zuendung: Double) {
        let mx = g.width * 0.5, my = g.height * 0.41, R = min(g.width, g.height) * 0.32
        func glanz(_ x: Double, _ y: Double, _ r: Double, _ farbe: Color, _ a: Double) {
            guard a > 0.01 else { return }
            let rect = CGRect(x: x - r * 4, y: y - r * 4, width: r * 8, height: r * 8)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [farbe.opacity(a), farbe.opacity(0)]),
                                                                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 4))
        }
        // Strahlen: zwei gegenläufige Kränze
        let strahlenAn = min(1, max(0, (t - 0.5) / 1.8))
        if strahlenAn > 0 {
            let kraenze: [(Int, Double, Color, Double)] = [
                (22, 2 * Double.pi / 40, Color(red: 1, green: 0.84, blue: 0.94), 0.09),
                (16, -2 * Double.pi / 55, Color(red: 0.75, green: 0.6, blue: 1), 0.06),
            ]
            for (anzahl, tempo, farbe, breite) in kraenze {
                for i in 0..<anzahl {
                    let w = Double(i) / Double(anzahl) * 2 * .pi + t * tempo
                    var p = Path()
                    p.move(to: CGPoint(x: mx, y: my))
                    p.addLine(to: CGPoint(x: mx + cos(w - breite / 2) * R * 4, y: my + sin(w - breite / 2) * R * 4))
                    p.addLine(to: CGPoint(x: mx + cos(w + breite / 2) * R * 4, y: my + sin(w + breite / 2) * R * 4))
                    p.closeSubpath()
                    ctx.fill(p, with: .radialGradient(Gradient(colors: [farbe.opacity(0.22 * strahlenAn), farbe.opacity(0)]),
                                                      center: CGPoint(x: mx, y: my), startRadius: R * 0.1, endRadius: R * 3))
                }
            }
        }
        // Glut im Takt
        let glut = t > 0.6 ? 0.15 + 0.55 * SplashSzene.schlag(max(t, 1.6)) : 0
        glanz(mx, my, R * 0.17, Color(red: 1, green: 0.94, blue: 0.98), glut)
        // Partikelring
        let ein = min(1, max(0, (t - 0.8) / 1.2))
        let schub = t > zuendung ? 3 * min(t - zuendung, 0.9) : 0
        let neig = -0.32
        if ein > 0 {
            for p in ring {
                let w = p.w + p.v * (t + schub)
                let rr = R * (1 + p.d)
                let ex = cos(w) * rr, ey = sin(w) * rr * 0.36
                let x = mx + ex * cos(neig) - ey * sin(neig), y = my + ex * sin(neig) + ey * cos(neig)
                let vorne = (sin(w) + 1) / 2
                glanz(x, y, p.r * (0.7 + vorne * 0.6), p.farbe, ein * (0.55 + 0.45 * sin(t * 4 + p.phase)) * (0.25 + vorne * 0.7))
            }
        }
        // Aufsteigende Funken
        for f in funken {
            let alter = (t + f.versatz).truncatingRemainder(dividingBy: f.leben)
            let y = g.height + 10 - f.tempo * alter
            let x = f.x * g.width + sin(alter * 1.5 + f.r * 3) * 6
            glanz(x, y, f.r, f.farbe, 0.85 * sin(.pi * alter / f.leben))
        }
        // Zündung: Blitz, Splitter, Druckwellen
        guard t > zuendung else { return }
        let dt = t - zuendung
        let blitz = dt < 0.13 ? dt / 0.13 : max(0, 1 - (dt - 0.13) / 1.17)
        if blitz > 0 {
            ctx.fill(Path(CGRect(origin: .zero, size: g)), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.95 * blitz), SplashSzene.farben[1].opacity(0.45 * blitz), .clear]),
                center: CGPoint(x: mx, y: my), startRadius: 0, endRadius: max(g.width, g.height) * 0.6))
        }
        for s in splitter where dt < s.leben {
            let weite = s.tempo * (1 - exp(-0.48 * dt)) / 0.48
            glanz(mx + cos(s.winkel) * weite, my + sin(s.winkel) * weite + 15 * dt * dt, s.r, s.farbe, 0.9 * sin(.pi * dt / s.leben))
        }
        let wellen: [(Double, Double, Color)] = [(0.0, 1.17, .white), (0.17, 1.33, SplashSzene.farben[1])]
        for (verz, dauer, farbe) in wellen {
            let k = (dt - verz) / dauer
            guard k > 0, k < 1 else { continue }
            let r = R * (0.4 + k * 2.4)
            ctx.stroke(Path(ellipseIn: CGRect(x: mx - r, y: my - r * 0.9, width: r * 2, height: r * 1.8)),
                       with: .color(farbe.opacity(0.75 * (1 - k))), lineWidth: 3 * (1 - k) + 0.5)
        }
    }
}
