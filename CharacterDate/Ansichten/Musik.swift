import SwiftUI
import UniformTypeIdentifiers

/// Lied im Chat: dein hochgeladenes Lied oder ihr Cover (Player mit Fortschritt, Songtext).
struct MusikKarte: View {
    @Environment(Verbindung.self) private var v
    let m: Nachricht
    @State private var textOffen = false
    @State private var datei: URL?
    @State private var dreht = false
    @State private var hinweis: String?
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
                    Text(ich ? (m.m("titel")?.text ?? "Dein Lied") : (m.m("titel")?.text ?? "Cover")).font(.subheadline.bold()).lineLimit(1)
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
            HStack(spacing: 10) {
                if let datei {
                    ShareLink(item: datei) { Label("Sichern", systemImage: "square.and.arrow.down") }
                } else if pfad != nil {
                    Button { Task { await vorbereiten() } } label: { Label("Sichern", systemImage: "square.and.arrow.down") }
                }
                if !ich, m.m("status")?.text == "fertig" {
                    Button { Task { await musikvideo() } } label: {
                        Label(dreht ? "Startet …" : "Musikvideo", systemImage: "film")
                    }.disabled(dreht)
                }
                Spacer(minLength: 0)
            }
            .font(.caption.bold())
            if let hinweis { Text(hinweis).font(.caption2).foregroundStyle(Farbe.text2) }
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
        .task(id: pfad) { if pfad != nil { await vorbereiten() } }
        .background(LinearGradient(colors: [Color(red: 0.64, green: 0.42, blue: 0.98).opacity(ich ? 0.4 : 0.22),
                                            Farbe.rose.opacity(ich ? 0.4 : 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension MusikKarte {
    /// Datei mit dem Liedtitel als Namen ablegen → »Sichern« öffnet das Teilen-Menü (Dateien, AirDrop, Musik-Apps …).
    @MainActor func vorbereiten() async {
        guard let pfad = m.m("audio")?.text, let d = try? await v.medien(pfad) else { return }
        let name = (m.m("titel")?.text ?? (m.vonMir ? "Mein Lied" : "Cover"))
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + "." + (pfad.split(separator: ".").last.map(String.init) ?? "mp3"))
        try? d.write(to: url, options: .atomic)
        datei = url
    }

    @MainActor func musikvideo() async {
        dreht = true
        do {
            _ = try await v.roh("/api/nachrichten/\(m.id)/musikvideo", methode: "POST", rohJSON: Data("{}".utf8))
            hinweis = "Das Musikvideo wird gedreht – das dauert eine Weile."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch { hinweis = error.localizedDescription; dreht = false }
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
    @State private var naehe: Double = 60
    @State private var genres: [String] = []
    @State private var alleGenres: [String] = []
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
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Nähe zum Original")
                            Spacer()
                            Text("\(Int(naehe)) %").bold().monospacedDigit().foregroundStyle(Farbe.rose)
                        }
                        Slider(value: $naehe, in: 0...100, step: 5).tint(Farbe.rose)
                        HStack {
                            Text("Neu gedacht").foregroundStyle(Farbe.text3)
                            Spacer()
                            Text(Self.naeheText(Int(naehe))).foregroundStyle(Farbe.text2)
                            Spacer()
                            Text("Cover").foregroundStyle(Farbe.text3)
                        }.font(.caption2)
                    }
                    if naehe < 100 && !alleGenres.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(genres.count > 1 ? "Musikstil – Mix aus \(genres.count)" : "Musikstil (mehrere = Mix)")
                                .font(.caption).foregroundStyle(Farbe.text2)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHGrid(rows: [GridItem(.fixed(30)), GridItem(.fixed(30)), GridItem(.fixed(30))], spacing: 6) {
                                    ForEach(alleGenres, id: \.self) { g in
                                        let an = genres.contains(g)
                                        Button {
                                            if an { genres.removeAll { $0 == g } } else if genres.count < 6 { genres.append(g) }
                                            UISelectionFeedbackGenerator().selectionChanged()
                                        } label: {
                                            Text(g).font(.caption.bold()).padding(.horizontal, 10).frame(height: 28)
                                                .background(an ? AnyShapeStyle(Farbe.verlauf) : AnyShapeStyle(Color.white.opacity(0.06)), in: Capsule())
                                                .overlay(Capsule().stroke(an ? .clear : Farbe.linie))
                                                .foregroundStyle(an ? .white : Farbe.text2)
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.vertical, 2)
                            }
                        }
                    }
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
            .task {
                struct G: Decodable { let genres: [String] }
                if let g: G = try? await v.anfrage("/api/musik/genres") { alleGenres = g.genres }
            }
            .fileImporter(isPresented: $waehlen, allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio]) { r in
                if case .success(let u) = r { datei = u }
            }
        }
    }

    static func naeheText(_ a: Int) -> String {
        if a >= 100 { return "wie das Original, nur ihre Stimme" }
        if a >= 80 { return "sehr nah am Original" }
        if a >= 50 { return "Originalmelodie, dein Stil" }
        if a >= 20 { return "frei interpretiert" }
        return "komplett neu gedacht"
    }

    @MainActor private func los() async {
        guard let u = datei else { return }
        arbeitet = true; defer { arbeitet = false }
        let zugriff = u.startAccessingSecurityScopedResource()
        defer { if zugriff { u.stopAccessingSecurityScopedResource() } }
        do {
            let d = try Data(contentsOf: u)
            let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            struct A: Decodable {}
            let typ = UTType(filenameExtension: u.pathExtension)?.preferredMIMEType ?? "audio/mpeg"
            let _: A = try await v.hochladen("/api/charaktere/\(c.id)/lied", datei: d, name: u.lastPathComponent, typ: typ,
                                             felder: ["prompt": p, "aehnlichkeit": String(Int(naehe)),
                                                      "genres": genres.joined(separator: ","), "musikvideo": video ? "1" : "0"])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            schliessen()
        } catch { fehler = error.localizedDescription }
    }
}

/// Fehlgeschlagene Erstellung mit »Nochmal versuchen« (Cover, Foto, Video).
struct Fehlgeschlagen: View {
    @Environment(Verbindung.self) private var v
    let m: Nachricht
    let text: String
    @State private var laeuft = false
    @State private var fehler: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.footnote)
            if let f = fehler ?? m.m("fehler")?.text {
                Text(String(f.prefix(160))).font(.caption2).foregroundStyle(Farbe.text3)
            }
            Button {
                Task {
                    laeuft = true
                    do { _ = try await v.roh("/api/nachrichten/\(m.id)/nochmal", methode: "POST") }
                    catch { fehler = error.localizedDescription; laeuft = false }
                }
            } label: { Label(laeuft ? "Startet …" : "Nochmal versuchen", systemImage: "arrow.clockwise") }
                .font(.caption.bold()).disabled(laeuft)
        }
        .padding(10).glas(16)
    }
}
