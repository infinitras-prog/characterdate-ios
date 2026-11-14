import SwiftUI

/// Designsystem wie am PC: dunkle Glasflächen, Violett für Bedienung, Rose für Gefühl, Mint für Status.
enum Farbe {
    static let grund = Color(red: 0.067, green: 0.063, blue: 0.106)
    static let flaeche = Color(red: 0.14, green: 0.125, blue: 0.21).opacity(0.72)
    static let linie = Color(red: 0.75, green: 0.63, blue: 1.0).opacity(0.14)
    static let violett = Color(red: 0.64, green: 0.42, blue: 0.98)
    static let rose = Color(red: 0.94, green: 0.39, blue: 0.71)
    static let mint = Color(red: 0.32, green: 0.84, blue: 0.69)
    static let text2 = Color.white.opacity(0.68)
    static let text3 = Color.white.opacity(0.45)
    static let verlauf = LinearGradient(colors: [violett, rose], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Lebendiger Hintergrund wie am PC: drei weiche Lichtflecken (Rosé, Violett, Bernstein) wandern langsam.
struct Hintergrund: View {
    @Environment(\.accessibilityReduceMotion) private var ruhig
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: ruhig)) { zeit in
            let t = zeit.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    Farbe.grund
                    fleck(Farbe.rose.opacity(0.30), r: w * 0.9,
                          x: w * (0.85 + 0.12 * sin(t / 9)), y: h * (0.05 + 0.08 * cos(t / 11)))
                    fleck(Farbe.violett.opacity(0.32), r: w * 1.0,
                          x: w * (0.1 + 0.15 * cos(t / 12)), y: h * (0.85 + 0.07 * sin(t / 10)))
                    fleck(Color(red: 0.96, green: 0.72, blue: 0.38).opacity(0.10), r: w * 0.6,
                          x: w * (0.5 + 0.25 * sin(t / 14)), y: h * (0.45 + 0.15 * cos(t / 13)))
                }
            }
        }
        .ignoresSafeArea()
    }

    private func fleck(_ farbe: Color, r: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(RadialGradient(colors: [farbe, .clear], center: .center, startRadius: 0, endRadius: r / 2))
            .frame(width: r, height: r).position(x: x, y: y).blendMode(.screen)
    }
}

/// Startbildschirm: Herz-Video aus NitraX in Schleife, Schriftzug mit Lichtschimmer, Funken – dann weiche Blende.
struct Splash: View {
    let fertig: () -> Void
    @State private var schrift = false
    @State private var schimmer = false
    @State private var weg = false
    var body: some View {
        ZStack {
            Farbe.grund.ignoresSafeArea()
            SchleifenVideo(name: "splash").ignoresSafeArea().scaleEffect(weg ? 1.15 : 1.02)
            LinearGradient(colors: [.clear, Farbe.grund.opacity(0.92)], startPoint: .center, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 10) {
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("Character").foregroundStyle(.white)
                    Text("Date").foregroundStyle(Farbe.verlauf)
                        .overlay(
                            LinearGradient(colors: [.clear, .white.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 60).offset(x: schimmer ? 90 : -90).blendMode(.overlay)
                                .mask(Text("Date"))
                        )
                    Text("AI").font(.system(size: 14, weight: .semibold)).tracking(3)
                        .foregroundStyle(Color(red: 0.96, green: 0.72, blue: 0.38)).padding(.leading, 6)
                }
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .opacity(schrift ? 1 : 0).offset(y: schrift ? 0 : 16).blur(radius: schrift ? 0 : 8)
                Text("Deine Begleitung erwacht …").font(.footnote).foregroundStyle(Farbe.text2).opacity(schrift ? 1 : 0)
                Spacer().frame(height: 70)
            }
        }
        .opacity(weg ? 0 : 1)
        .onAppear {
            withAnimation(.spring(duration: 0.9).delay(0.3)) { schrift = true }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false).delay(1.0)) { schimmer = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
                withAnimation(.easeInOut(duration: 0.8)) { weg = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { fertig() }
            }
        }
    }
}

struct Glas: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
    }
}

extension View {
    func glas(_ radius: CGFloat = 22) -> some View { modifier(Glas(radius: radius)) }
}

struct HauptKnopf: ButtonStyle {
    var farbe: AnyShapeStyle = AnyShapeStyle(Farbe.verlauf)
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).frame(height: 48)
            .background(farbe, in: Capsule())
            .shadow(color: Farbe.rose.opacity(0.35), radius: 12, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct Chip: View {
    let text: String
    var farbe: Color = Farbe.violett
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(farbe.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(farbe.opacity(0.35), lineWidth: 1))
    }
}

/// Fortschrittsring der Kennenlern-Kurve.
struct Ring: View {
    let wert: Double
    let oben: String
    var unten: String? = nil
    var groesse: CGFloat = 86
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
            Circle().trim(from: 0, to: max(0.02, min(1, wert)))
                .stroke(AngularGradient(colors: [Farbe.violett, Farbe.rose, Farbe.violett], center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(oben).font(.system(size: groesse * 0.22, weight: .semibold, design: .rounded))
                if let unten { Text(unten).font(.system(size: 10)).foregroundStyle(Farbe.text3) }
            }
        }
        .frame(width: groesse, height: groesse)
    }
}

func uhrzeit(_ ts: Double) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "de_AT"); f.dateFormat = "HH:mm"
    return f.string(from: Date(timeIntervalSince1970: ts))
}

func tagText(_ ts: Double) -> String {
    let d = Date(timeIntervalSince1970: ts)
    if Calendar.current.isDateInToday(d) { return "Heute" }
    if Calendar.current.isDateInYesterday(d) { return "Gestern" }
    let f = DateFormatter(); f.locale = Locale(identifier: "de_AT"); f.dateFormat = "EEEE, d. MMMM"
    return f.string(from: d)
}

func onlineText(_ v: String) -> String {
    v == "ja" ? "Online" : v == "kurz" ? "Beschäftigt" : "Gerade nicht erreichbar"
}
