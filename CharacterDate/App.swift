import SwiftUI
import LocalAuthentication

@main
struct CharacterDateApp: App {
    @State private var verbindung = Verbindung()
    @AppStorage("faceid") private var faceID = false
    @State private var gesperrt = true
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ZStack {
                Hintergrund()
                if !verbindung.gekoppelt {
                    KopplungAnsicht()
                } else {
                    HauptAnsicht()
                }
                if faceID && gesperrt { Sperre { gesperrt = false } }
            }
            .environment(verbindung)
            .preferredColorScheme(.dark)
            .tint(Farbe.rose)
            .task { if verbindung.gekoppelt { await verbindung.verbinden() } }
            .onChange(of: phase) { _, neu in
                if neu == .background { gesperrt = true }
                if neu == .active, verbindung.gekoppelt, verbindung.zustand != .verbunden {
                    Task { await verbindung.verbinden() }
                }
            }
        }
    }
}

/// Face ID vor den Chats (abschaltbar in den Einstellungen).
struct Sperre: View {
    let entsperrt: () -> Void
    @State private var meldung: String?
    var body: some View {
        ZStack {
            Hintergrund()
            VStack(spacing: 18) {
                Herz(groesse: 64)
                Text("CharacterDate").font(.system(size: 28, weight: .semibold, design: .rounded))
                if let meldung { Text(meldung).font(.footnote).foregroundStyle(Farbe.text2) }
                Button("Entsperren") { pruefen() }.buttonStyle(HauptKnopf())
            }
        }
        .onAppear { pruefen() }
    }
    private func pruefen() {
        let k = LAContext()
        var fehler: NSError?
        guard k.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fehler) else { entsperrt(); return }
        k.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Deine Chats öffnen") { ok, _ in
            DispatchQueue.main.async { if ok { entsperrt() } else { meldung = "Nicht entsperrt." } }
        }
    }
}

struct Herz: View {
    var groesse: CGFloat = 40
    var body: some View {
        Image(systemName: "heart")
            .font(.system(size: groesse, weight: .semibold))
            .foregroundStyle(Farbe.verlauf)
            .shadow(color: Farbe.rose.opacity(0.5), radius: 12)
    }
}
