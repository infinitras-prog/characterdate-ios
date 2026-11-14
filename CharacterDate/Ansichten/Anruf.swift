import SwiftUI

/// Vollbild-Telefonat: verschwommenes Porträt, pulsierender Ring (leuchtet, wenn sie spricht), Untertitel.
struct AnrufAnsicht: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    let c: Charakter
    @State private var telefon = Telefon()
    @State private var puls = false

    var body: some View {
        ZStack {
            Farbe.grund.ignoresSafeArea()
            if let a = c.avatarUrl {
                NetzBild(pfad: a).ignoresSafeArea().blur(radius: 40).opacity(0.55).scaleEffect(1.2)
            }
            LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 40)
                ring
                Text(c.name).font(.system(size: 32, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(statusText).font(.headline.monospacedDigit()).foregroundStyle(Farbe.text2)
                }
                if let i = telefon.grund ?? telefon.info {
                    Text(i).font(.footnote).foregroundStyle(Farbe.text3).multilineTextAlignment(.center).padding(.horizontal, 30)
                }
                Spacer()
                untertitel
                Spacer()
                knoepfe.padding(.bottom, 30)
            }
            .foregroundStyle(.white)
        }
        .statusBarHidden(telefon.zustand == .aktiv)
        .onAppear {
            telefon.starten(v, char: c)
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { puls = true }
        }
        .onDisappear { if telefon.zustand != .beendet { telefon.beenden() } }
        .onChange(of: telefon.zustand) { _, z in
            if z == .beendet {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                DispatchQueue.main.asyncAfter(deadline: .now() + (telefon.grund == nil ? 1.2 : 3)) { schliessen() }
            } else if z == .aktiv {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    private var statusText: String {
        switch telefon.zustand {
        case .waehlt: return "Wählt …"
        case .klingelt: return "Klingelt …"
        case .beendet: return "Anruf beendet"
        case .aktiv:
            let s = Int(Date().timeIntervalSince(telefon.start ?? Date()))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }

    private var ring: some View {
        let sie = CGFloat(telefon.pegelSie)
        let klingelt = telefon.zustand != .aktiv && telefon.zustand != .beendet
        return ZStack {
            ForEach(0..<3) { i in
                Circle().stroke(Farbe.verlauf, lineWidth: 2)
                    .frame(width: 190, height: 190)
                    .scaleEffect(klingelt ? (puls ? 1.0 + CGFloat(i + 1) * 0.16 : 1.0) : 1.0 + sie * CGFloat(i + 1) * 0.12)
                    .opacity(klingelt ? (puls ? 0 : 0.6) : Double(0.15 + sie * 0.6) / Double(i + 1))
            }
            Circle().fill(Farbe.verlauf).frame(width: 196, height: 196).blur(radius: 18).opacity(0.25 + Double(sie) * 0.6)
            Avatar(c: c, groesse: 180)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .scaleEffect(1 + sie * 0.04)
        }
        .animation(.easeOut(duration: 0.12), value: telefon.pegelSie)
        .frame(height: 260)
    }

    private var untertitel: some View {
        VStack(spacing: 10) {
            if !telefon.sieText.isEmpty {
                Text(telefon.sieText).font(.title3.weight(.medium)).multilineTextAlignment(.center)
                    .transition(.opacity).id("sie" + telefon.sieText)
            }
            if !telefon.duText.isEmpty {
                Text("Du: \(telefon.duText)").font(.subheadline).foregroundStyle(Farbe.text2).multilineTextAlignment(.center)
                    .transition(.opacity).id("du" + telefon.duText)
            }
        }
        .padding(.horizontal, 28)
        .animation(.easeOut(duration: 0.3), value: telefon.sieText + telefon.duText)
        .frame(minHeight: 110)
    }

    private var knoepfe: some View {
        HStack(spacing: 34) {
            rund(telefon.stumm ? "mic.slash.fill" : "mic.fill", text: telefon.stumm ? "Stumm" : "Mikro", an: telefon.stumm) {
                telefon.stummSchalten()
            }
            Button { telefon.auflegen() } label: {
                Image(systemName: "phone.down.fill").font(.system(size: 30, weight: .semibold))
                    .frame(width: 78, height: 78).background(Color.red, in: Circle())
                    .shadow(color: .red.opacity(0.5), radius: 16)
            }
            .accessibilityLabel("Auflegen")
            .disabled(telefon.zustand == .beendet)
            rund(telefon.lautsprecher ? "speaker.wave.3.fill" : "speaker.fill", text: "Lautsprecher", an: telefon.lautsprecher) {
                telefon.lautsprecherSchalten()
            }
        }
    }

    private func rund(_ symbol: String, text: String, an: Bool, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .background(an ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.14)), in: Circle())
                    .foregroundStyle(an ? Color.black : Color.white)
                Text(text).font(.caption2).foregroundStyle(Farbe.text2)
            }
        }
        .disabled(telefon.zustand == .beendet)
    }
}
