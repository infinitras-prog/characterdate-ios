import SwiftUI
import PhotosUI

// MARK: - Charakter erstellen

/// Schnell-Erstellung wie am PC: Beschreibung → Profil (vom Sprachmodell ergänzt) → optional Referenzbild.
/// Die feine Einstellung (DNA, Stimme, Bilder) bleibt dem Editor am PC vorbehalten.
struct ErstellenAnsicht: View {
    @Environment(Verbindung.self) private var v
    let fertig: (Charakter) -> Void
    @State private var beschreibung = ""
    @State private var foto: PhotosPickerItem?
    @State private var fotoDaten: Data?
    @State private var arbeitet: String?
    @State private var fehler: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Marke()
                Text("Charakter erstellen").font(.title2.weight(.semibold))
                Text("Beschreib sie in ein paar Sätzen. Der Rest wird stimmig ergänzt. Feinheiten wie Stimme, Bilder und Tagesablauf stellst du am PC im Editor ein.")
                    .font(.subheadline).foregroundStyle(Farbe.text2)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Beschreibung", systemImage: "wand.and.stars").font(.headline)
                    TextField("z. B. Sophie, 24, Grafikdesignerin aus Wien. Verspielt, kreativ, liebt Indie-Konzerte und Bouldern …",
                              text: $beschreibung, axis: .vertical)
                        .lineLimit(4...10).padding(12).background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(16).glas()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Referenzbild (optional)", systemImage: "photo.on.rectangle").font(.headline)
                    Text("Ein klares Gesicht von vorne. Nur Bilder von erfundenen Figuren, von dir oder von Menschen, die zugestimmt haben.")
                        .font(.caption).foregroundStyle(Farbe.text3)
                    HStack {
                        if let fotoDaten, let b = UIImage(data: fotoDaten) {
                            Image(uiImage: b).resizable().scaledToFill().frame(width: 84, height: 104).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        PhotosPicker(selection: $foto, matching: .images) {
                            Label(fotoDaten == nil ? "Bild wählen" : "Anderes Bild", systemImage: "plus").padding(.horizontal, 14).frame(height: 40).glas(12)
                        }
                    }
                }
                .padding(16).glas()

                if let fehler { Text(fehler).font(.footnote).foregroundStyle(Farbe.rose) }
                Button { Task { await erstellen() } } label: {
                    HStack { Image(systemName: "sparkles"); Text(arbeitet ?? "Charakter erstellen") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(HauptKnopf())
                .disabled(arbeitet != nil || beschreibung.trimmingCharacters(in: .whitespaces).count < 10)
            }
            .padding(16)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: foto) { _, neu in
            Task { fotoDaten = try? await neu?.loadTransferable(type: Data.self) }
        }
    }

    @MainActor
    private func erstellen() async {
        fehler = nil
        do {
            arbeitet = "Profil entsteht …"
            // DNA unverändert durchreichen (der Decoder würde snake_case-Schlüssel umbenennen)
            let dna = try await v.roh("/api/charaktere/aus_beschreibung", methode: "POST", body: ["text": beschreibung], zeit: 180)
            arbeitet = "Wird gespeichert …"
            var hülle = Data("{\"entwurf\": false, \"dna\": ".utf8)
            hülle.append(dna)
            hülle.append(Data("}".utf8))
            var c: Charakter = try await v.anfrageRoh("/api/charaktere", json: hülle)
            if let d = fotoDaten, let b = UIImage(data: d), let jpg = b.jpegData(compressionQuality: 0.9) {
                arbeitet = "Bild wird hochgeladen …"
                c = try await v.hochladen("/api/charaktere/\(c.id)/referenz", datei: jpg, name: "referenz.jpg", typ: "image/jpeg")
            }
            await v.neuLaden()
            beschreibung = ""; fotoDaten = nil; arbeitet = nil
            fertig(c)
        } catch {
            arbeitet = nil
            fehler = error.localizedDescription
        }
    }
}

// MARK: - Galerie

struct GalerieAnsicht: View {
    @Environment(Verbindung.self) private var v
    @State private var bilder: [Bild] = []
    @State private var art = ""
    @State private var gross: GrossesBild?
    private let spalten = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    private let arten: [(String, String)] = [("", "Alle"), ("selfie", "Ihre Fotos"), ("wirfoto", "Unsere"), ("studio", "Studio"), ("von_dir", "Von dir")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Marke()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(arten, id: \.0) { a in
                            Button(a.1) { art = a.0 }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(art == a.0 ? AnyShapeStyle(Farbe.verlauf) : AnyShapeStyle(Color.white.opacity(0.06)), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
                if bilder.isEmpty {
                    Text("Noch keine Bilder. Bitte sie im Chat um ein Foto.").font(.subheadline).foregroundStyle(Farbe.text2)
                        .padding(30).frame(maxWidth: .infinity).glas()
                }
                LazyVGrid(columns: spalten, spacing: 8) {
                    ForEach(bilder) { b in
                        NetzBild(pfad: b.url).frame(height: 220).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onTapGesture { gross = GrossesBild(pfad: b.url, bildId: b.id) }
                    }
                }
            }
            .padding(16)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: art) { await laden() }
        .refreshable { await laden() }
        .fullScreenCover(item: $gross) { b in BildVollbild(bild: b, geaendert: { Task { await laden() } }) }
    }

    @MainActor
    private func laden() async {
        let pfad = art.isEmpty ? "/api/galerie" : "/api/galerie?art=\(art)"
        if let b: [Bild] = try? await v.anfrage(pfad) { bilder = b }
    }
}

// MARK: - Einstellungen

struct EinstellungenAnsicht: View {
    @Environment(Verbindung.self) private var v
    @AppStorage("faceid") private var faceID = false
    @State private var entkoppelnFrage = false

    var body: some View {
        Form {
            Section("Verbindung") {
                LabeledContent("PC", value: v.pcName)
                LabeledContent("Zustand", value: v.zustand == .verbunden ? "Verbunden" : v.zustand == .verbindet ? "Verbinde …" : "Nicht verbunden")
                if let b = v.basis { LabeledContent("Adresse", value: b.absoluteString) }
                ForEach(v.adressen, id: \.self) { a in Text(a).font(.caption).foregroundStyle(Farbe.text3) }
                Button("Neu verbinden") { Task { await v.verbinden() } }
            }
            Section {
                Toggle("Mit Face ID schützen", isOn: $faceID)
            } header: { Text("Privatsphäre") } footer: {
                Text("Chats, Bilder und Erinnerungen liegen verschlüsselt auf deinem PC. Das iPhone zeigt sie nur an.")
            }
            Section {
                Text("Modelle, Stimmen, Bild-Einstellungen und der Store werden am PC verwaltet.")
                    .font(.footnote).foregroundStyle(Farbe.text2)
            }
            Section {
                Button("Vom PC entkoppeln", role: .destructive) { entkoppelnFrage = true }
            }
            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Einstellungen")
        .confirmationDialog("Vom PC entkoppeln?", isPresented: $entkoppelnFrage, titleVisibility: .visible) {
            Button("Entkoppeln", role: .destructive) { v.entkoppeln() }
        } message: {
            Text("Danach brauchst du einen neuen QR-Code vom PC. Am PC kannst du das Gerät zusätzlich unter Einstellungen → iPhone entfernen.")
        }
    }
}
