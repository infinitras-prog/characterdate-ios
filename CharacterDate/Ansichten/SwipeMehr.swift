import SwiftUI
import CoreLocation

// MARK: - Langes Drücken auf einen Charakter (wie Rechtsklick am PC)

/// Kontextmenü für Charaktere: Chat leeren, Löschen bzw. bei Swipe-Matches Entmatchen – mit Rückfrage.
struct CharMenue: ViewModifier {
    @Environment(Verbindung.self) private var v
    let c: Charakter
    var oeffnen: (() -> Void)? = nil
    @State private var frage: String?          // "leeren" | "loeschen"

    private var swipe: Bool { c.dna.swipe == true }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let oeffnen { Button { oeffnen() } label: { Label("Chat öffnen", systemImage: "bubble.left.and.bubble.right") } }
                Button { frage = "leeren" } label: { Label("Chatverlauf leeren", systemImage: "eraser") }
                Button(role: .destructive) { frage = "loeschen" } label: {
                    Label(swipe ? "Entmatchen" : "Charakter löschen", systemImage: swipe ? "heart.slash" : "trash")
                }
            }
            .confirmationDialog(titel, isPresented: Binding(get: { frage != nil }, set: { if !$0 { frage = nil } }), titleVisibility: .visible) {
                Button(frage == "leeren" ? "Leeren" : swipe ? "Entmatchen" : "Endgültig löschen", role: .destructive) {
                    let art = frage
                    Task {
                        _ = try? await v.roh("/api/charaktere/\(c.id)" + (art == "leeren" ? "/chat" : ""), methode: "DELETE")
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        await v.neuLaden()
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { Text(text) }
    }

    private var titel: String {
        frage == "leeren" ? "Chat mit \(c.name) leeren?" : swipe ? "\(c.name) entmatchen?" : "\(c.name) löschen?"
    }
    private var text: String {
        if frage == "leeren" { return "Alle Nachrichten verschwinden. Sie selbst, ihre Erinnerungen und eure Galerie bleiben." }
        return swipe ? "Wie auf Tinder: Der Chat ist weg, und Fotos, Stimme und alles von ihr werden von der Festplatte gelöscht."
            : "Chat, Erinnerungen, Fotos, Videos, Lieder und Stimme werden komplett gelöscht. Das lässt sich nicht rückgängig machen."
    }
}

extension View {
    func charMenue(_ c: Charakter, oeffnen: (() -> Void)? = nil) -> some View { modifier(CharMenue(c: c, oeffnen: oeffnen)) }
}

// MARK: - Bild-Infos (Modell, LoRAs, Prompt)

struct BildInfoBlatt: View {
    @Environment(\.dismiss) private var schliessen
    let b: Bild

    private func s(_ k: String) -> String? {
        guard let w = b.meta?[k] else { return nil }
        if let t = w.text, !t.isEmpty { return t }
        if let z = w.zahl { return z == z.rounded() ? String(Int(z)) : String(format: "%.1f", z) }
        return nil
    }
    private func kurz(_ n: String) -> String {
        let letzter = n.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? n
        return letzter.replacingOccurrences(of: ".safetensors", with: "").replacingOccurrences(of: ".gguf", with: "")
    }
    private var loras: [(String, Double)] {
        guard case .liste(let l)? = b.meta?["loras"] else { return [] }
        return l.compactMap { e in
            guard case .objekt(let o) = e, let n = o["name"]?.text else { return nil }
            return (kurz(n), o["staerke"]?.zahl ?? 1)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Bild") {
                    LabeledContent("Art", value: b.art)
                    LabeledContent("Erstellt", value: Date(timeIntervalSince1970: b.erstellt).formatted(date: .abbreviated, time: .shortened))
                    if let m = s("modell") { LabeledContent("Modell", value: kurz(m)) }
                    if let f = s("familie") { LabeledContent("Familie", value: f) }
                    if let st = s("stil") { LabeledContent("Stil", value: st) }
                    if let sd = s("seed") { LabeledContent("Seed", value: sd) }
                    if let q = s("qualitaet") { LabeledContent("Qualität", value: q) }
                    if let sek = s("sekunden") { LabeledContent("Länge", value: "\(sek) s") }
                    if let r = s("rechenzeit") { LabeledContent("Rechenzeit", value: "\(r) s") }
                }
                Section("LoRAs") {
                    if loras.isEmpty { Text("keine").foregroundStyle(Farbe.text3) }
                    ForEach(loras, id: \.0) { l in LabeledContent(l.0, value: String(format: "%.2f", l.1)) }
                }
                if let p = s("prompt") {
                    Section("Prompt") {
                        Text(p).font(.footnote).textSelection(.enabled)
                        Button { UIPasteboard.general.string = p } label: { Label("Prompt kopieren", systemImage: "doc.on.doc") }
                    }
                }
                if let p = s("plan") { Section("Überlegung des Bild-Agenten") { Text(p).font(.footnote) } }
            }
            .scrollContentBackground(.hidden)
            .background(Hintergrund())
            .navigationTitle(s("kurz") ?? "Infos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliessen() } } }
        }
    }
}

/// Video aus der Galerie im Vollbild.
struct VideoBlatt: View {
    @Environment(\.dismiss) private var schliessen
    let pfad: String
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ChatVideo(pfad: pfad).aspectRatio(contentMode: .fit)
            Button { schliessen() } label: {
                Image(systemName: "xmark").font(.headline).padding(12).background(.black.opacity(0.5), in: Circle()).foregroundStyle(.white)
            }.padding()
        }
    }
}

// MARK: - Standort (echte Ortung vom iPhone)

@MainActor @Observable
final class Ortung: NSObject, CLLocationManagerDelegate {
    private let m = CLLocationManager()
    var laeuft = false
    var fehler: String?
    private var fertig: ((CLLocation) -> Void)?

    override init() { super.init(); m.delegate = self; m.desiredAccuracy = kCLLocationAccuracyKilometer }

    func holen(_ dann: @escaping (CLLocation) -> Void) {
        fehler = nil; laeuft = true; fertig = dann
        if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() } else { m.requestLocation() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard laeuft else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted: laeuft = false; fehler = "Ortung ist aus – in den iPhone-Einstellungen erlauben oder Stadt wählen."
            default: break
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in laeuft = false; fertig?(l); fertig = nil }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in laeuft = false; fehler = "Ortung ging nicht – wähl deine Stadt." }
    }
}

struct StandortZeile: View {
    @Environment(Verbindung.self) private var v
    @State private var ortung = Ortung()
    @State private var name: String?
    @State private var staedte: [String] = []
    @State private var wahl = ""

    private struct OrtAntwort: Decodable { struct O: Decodable { let name: String; let quelle: String? }; let ort: O }

    var body: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dein Standort")
                    Text(name ?? "Noch nicht festgelegt").font(.caption).foregroundStyle(Farbe.text2)
                }
                Spacer()
                Button { orten() } label: {
                    if ortung.laeuft { ProgressView() } else { Label("Orten", systemImage: "location.fill") }
                }.buttonStyle(.bordered).tint(Farbe.rose)
            }
            if let f = ortung.fehler { Text(f).font(.caption).foregroundStyle(.orange) }
            Picker("… oder Stadt", selection: $wahl) {
                Text("Stadt wählen").tag("")
                ForEach(staedte, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: wahl) { _, n in if !n.isEmpty { Task { await setzen(stadt: n) } } }
        }
        .task {
            if let s: [String] = try? await v.anfrage("/api/tank/staedte") { staedte = s }
            if let st: TankStatusOrt = try? await v.anfrage("/api/tank/status") { name = st.einstellungen?.ort?.name }
        }
    }

    private func orten() {
        ortung.holen { l in Task { await setzen(lat: l.coordinate.latitude, lon: l.coordinate.longitude) } }
    }
    @MainActor private func setzen(lat: Double? = nil, lon: Double? = nil, stadt: String? = nil) async {
        struct B: Encodable { let lat: Double?; let lon: Double?; let stadt: String? }
        if let a: OrtAntwort = try? await v.anfrage("/api/tank/standort", methode: "POST", body: B(lat: lat, lon: lon, stadt: stadt)) {
            name = a.ort.name + (a.ort.quelle == "ortung" ? " · per Ortung" : "")
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

private struct TankStatusOrt: Decodable {
    struct E: Decodable { struct O: Decodable { let name: String? }; let ort: O? }
    let einstellungen: E?
}

// MARK: - Mein Swipe-Profil

struct SwipeProfilBlatt: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    @State private var bio = ""
    @State private var sucht = ""
    @State private var alter = 25
    @State private var interessen = ""
    @State private var geladen = false
    private let suchen = ["Etwas Festes", "Langfristig, aber offen", "Mal schauen, was passiert", "Etwas Lockeres", "Freundschaft Plus", "Neue Leute kennenlernen"]

    var body: some View {
        NavigationStack {
            Form {
                if geladen {
                    Section { Text("Das sehen die Profile auf Swipe, bevor sie dich zurück liken. Ohne Foto liked kaum jemand zurück – Fotos legst du am PC unter »Mein Profil« an.")
                        .font(.footnote).foregroundStyle(Farbe.text2) }
                    Section("Über dich") {
                        Stepper("Alter: \(alter)", value: $alter, in: 18...99)
                        TextField("Bio – ein, zwei ehrliche Sätze", text: $bio, axis: .vertical).lineLimit(3...6)
                    }
                    Section("Du suchst") {
                        Picker("Du suchst", selection: $sucht) {
                            Text("–").tag("")
                            ForEach(suchen, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.inline).labelsHidden()
                    }
                    Section { TextField("z. B. Klettern, Kochen, Serien", text: $interessen) } header: { Text("Leidenschaften (mit Komma)") }
                        footer: { Text("Gemeinsame Leidenschaften machen ein Match wahrscheinlicher.") }
                } else { ProgressView() }
            }
            .scrollContentBackground(.hidden)
            .background(Hintergrund())
            .navigationTitle("Mein Swipe-Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { schliessen() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { Task { await sichern(); schliessen() } } }
            }
            .task { await laden() }
        }
    }

    private struct P: Decodable {
        struct S: Decodable { var bio: String?; var sucht: String?; var alter: Double?; var interessen: [String]? }
        var swipe: S?; var interessen: [String]?
    }
    private struct Sw: Encodable { let bio: String; let sucht: String; let alter: Int; let interessen: [String] }

    @MainActor private func laden() async {
        if let p: P = try? await v.anfrage("/api/profil") {
            bio = p.swipe?.bio ?? ""; sucht = p.swipe?.sucht ?? ""
            if let a = p.swipe?.alter { alter = Int(a) }
            interessen = (p.swipe?.interessen ?? p.interessen ?? []).joined(separator: ", ")
        }
        geladen = true
    }
    @MainActor private func sichern() async {
        let liste = interessen.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        _ = try? await v.roh("/api/profil/swipe", methode: "PUT", body: Sw(bio: bio, sucht: sucht, alter: alter, interessen: liste))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
