import SwiftUI
import UniformTypeIdentifiers

/// Lied im Chat: dein hochgeladenes Lied oder ihr Cover (Player mit Fortschritt, Songtext).
struct MusikKarte: View {
    @Environment(Verbindung.self) private var v
    let m: Nachricht
    @State private var textOffen = false
    private var spieler: Abspieler { Abspieler.shared }

    var body: some View {
        let ich = m.vonMir
        let pfad = m.m("audio")?.text
        let laeuft = pfad != nil && spieler.aktuell == pfad
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    if let pfad { Task { await spieler.umschalten(pfad, v: v) } }
                } label: {
                    Image(systemName: laeuft ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40).background(Farbe.verlauf, in: Circle()).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ich ? "Dein Lied" : (m.m("titel")?.text ?? "Cover")).font(.subheadline.bold()).lineLimit(1)
                    Text(ich ? (m.text.isEmpty ? "zum Covern" : m.text) : (m.m("stil")?.text ?? ""))
                        .font(.caption2).foregroundStyle(Farbe.text2).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "music.note").foregroundStyle(Farbe.rose.opacity(0.8))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(Farbe.verlauf).frame(width: g.size.width * (laeuft ? spieler.fortschritt : 0))
                }
            }.frame(height: 5)
            if !ich, m.m("lyrics")?.text != nil {
                Button(textOffen ? "Songtext aus" : "Songtext") { textOffen.toggle() }.font(.caption.bold())
                if textOffen {
                    Text(m.m("lyrics")?.text ?? "").font(.caption).foregroundStyle(Farbe.text2)
                        .padding(10).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(12)
        .frame(width: 270)
        .background(LinearGradient(colors: [Color(red: 0.64, green: 0.42, blue: 0.98).opacity(ich ? 0.4 : 0.22),
                                            Farbe.rose.opacity(ich ? 0.4 : 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Lied auswählen + Wunsch eingeben: sie singt ein Cover (optional mit Musikvideo).
struct LiedBlatt: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    let c: Charakter
    @State private var datei: URL?
    @State private var waehlen = false
    @State private var prompt = ""
    @State private var video = false
    @State private var arbeitet = false
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { waehlen = true } label: {
                        Label(datei?.lastPathComponent ?? "Lied auswählen (MP3, WAV, M4A …)", systemImage: "music.note.list")
                    }
                }
                Section {
                    TextField("z. B. als ruhige Akustik-Ballade mit Gitarre · als Rock-Version · nur ihre Stimme", text: $prompt, axis: .vertical)
                        .lineLimit(2...5)
                    Toggle(isOn: $video) { Label("Auch ein Musikvideo drehen", systemImage: "film") }.tint(Farbe.rose)
                } header: { Text("Wie soll sie es singen?") } footer: {
                    Text("YuE2 komponiert das Lied im gewünschten Stil neu, dann singt \(c.name) es mit ihrer Stimme (ca. 4 Minuten je Minute Song). Ein Musikvideo dauert deutlich länger – je Szene einige Minuten, lippensynchron.")
                }
                if let fehler { Section { Text(fehler).foregroundStyle(.orange) } }
                Section {
                    Button { Task { await los() } } label: {
                        Label(arbeitet ? "Lädt hoch …" : "Cover aufnehmen", systemImage: "mic.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(HauptKnopf()).disabled(arbeitet || datei == nil).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Hintergrund())
            .navigationTitle("\(c.name) singt dein Lied")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { schliessen() } } }
            .fileImporter(isPresented: $waehlen, allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio]) { r in
                if case .success(let u) = r { datei = u }
            }
        }
    }

    @MainActor private func los() async {
        guard let u = datei else { return }
        arbeitet = true; defer { arbeitet = false }
        let zugriff = u.startAccessingSecurityScopedResource()
        defer { if zugriff { u.stopAccessingSecurityScopedResource() } }
        do {
            let d = try Data(contentsOf: u)
            let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = video && p.range(of: "musikvideo", options: .caseInsensitive) == nil ? "Musikvideo. \(p)" : p
            struct A: Decodable {}
            let typ = UTType(filenameExtension: u.pathExtension)?.preferredMIMEType ?? "audio/mpeg"
            let _: A = try await v.hochladen("/api/charaktere/\(c.id)/lied", datei: d, name: u.lastPathComponent, typ: typ,
                                             felder: ["prompt": text])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            schliessen()
        } catch { fehler = error.localizedDescription }
    }
}
