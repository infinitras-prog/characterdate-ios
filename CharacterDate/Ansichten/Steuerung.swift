import SwiftUI

// MARK: - Regie (Hauptsprachmodell) – Schnellknopf oben

struct RegieModell: Decodable, Identifiable, Hashable { let id: String; let name: String }
struct RegieStand: Decodable {
    let modus: String
    let anbieter: String
    let apiModell: String
    let lokalModell: String
    let apiModelle: [RegieModell]
    let lokaleModelle: [RegieModell]
    let fehler: String?
}

struct RegieKnopf: View {
    @Environment(Verbindung.self) private var v
    @State private var stand: RegieStand?
    @State private var offen = false

    var body: some View {
        Button { offen = true } label: {
            // kleiner Chip mit Gehirn: das Sprachmodell (Regie) – Name steht im Auswahlblatt
            ZStack {
                Image(systemName: "cpu").font(.system(size: 22, weight: .regular))
                    .foregroundStyle(LinearGradient(colors: [Farbe.violett, Farbe.rose], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "brain").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Farbe.rose.opacity(0.45), lineWidth: 1))
            .shadow(color: Farbe.rose.opacity(0.35), radius: 6)
        }
        .accessibilityLabel("Regie-Modell wählen, aktuell \(kurzname)")
        .task { await laden() }
        .sheet(isPresented: $offen) { RegieWahl(stand: $stand) }
    }

    private var kurzname: String {
        guard let s = stand else { return "Regie" }
        if s.modus == "api" {
            let n = s.apiModelle.first(where: { $0.id == s.apiModell })?.name ?? s.apiModell
            return String(n.prefix(22))
        }
        return String(((s.lokalModell as NSString).lastPathComponent as NSString).deletingPathExtension.prefix(22))
    }

    @MainActor private func laden() async { stand = try? await v.anfrage("/api/handy/regie", zeit: 30) }
}

struct RegieWahl: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    @Binding var stand: RegieStand?
    @State private var suche = ""
    @State private var modus = "api"
    @State private var arbeitet = false
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Wo rechnet die Regie?", selection: $modus) {
                        Text("API (Cloud)").tag("api"); Text("Lokal (PC)").tag("lokal")
                    }.pickerStyle(.segmented)
                } footer: {
                    Text("Die Regie ist das Hauptsprachmodell: es schreibt ihre Nachrichten, plant Fotos, Videos und Dates.")
                }
                if let f = fehler ?? stand?.fehler { Section { Text(f).font(.footnote).foregroundStyle(.orange) } }
                Section(modus == "api" ? "Modelle von \(stand?.anbieter ?? "")" : "Modelle auf dem PC") {
                    ForEach(liste) { m in
                        Button { Task { await waehlen(m) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).foregroundStyle(.white)
                                    if m.name != m.id { Text(modus == "lokal" ? (m.id as NSString).lastPathComponent : m.id).font(.caption2).foregroundStyle(Farbe.text3) }
                                }
                                Spacer()
                                if aktiv(m) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Farbe.rose) }
                            }
                        }
                        .disabled(arbeitet)
                    }
                    if liste.isEmpty { Text("Keine Modelle gefunden.").foregroundStyle(Farbe.text3) }
                }
            }
            .searchable(text: $suche, prompt: "Modell suchen")
            .navigationTitle("Regie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliessen() } } }
            .onAppear { modus = stand?.modus ?? "api" }
            .task { if stand == nil { stand = try? await v.anfrage("/api/handy/regie", zeit: 30); modus = stand?.modus ?? "api" } }
        }
        .presentationDetents([.medium, .large])
    }

    private var liste: [RegieModell] {
        let alle = modus == "api" ? (stand?.apiModelle ?? []) : (stand?.lokaleModelle ?? [])
        let s = suche.trimmingCharacters(in: .whitespaces).lowercased()
        return s.isEmpty ? alle : alle.filter { $0.name.lowercased().contains(s) || $0.id.lowercased().contains(s) }
    }

    private func aktiv(_ m: RegieModell) -> Bool {
        guard let s = stand, s.modus == modus else { return false }
        return modus == "api" ? m.id == s.apiModell : m.id == s.lokalModell
    }

    @MainActor private func waehlen(_ m: RegieModell) async {
        arbeitet = true; defer { arbeitet = false }
        struct W: Encodable { let modus: String; let modell: String }
        do {
            stand = try await v.anfrage("/api/handy/regie", methode: "PUT", body: W(modus: modus, modell: m.id), zeit: 30)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch { fehler = error.localizedDescription }
    }
}

/// Zeile in den Einstellungen: aktuelle Regie + Auswahl.
struct RegieZeile: View {
    @Environment(Verbindung.self) private var v
    @State private var stand: RegieStand?
    @State private var offen = false
    var body: some View {
        Button { offen = true } label: {
            HStack {
                Label("Modell", systemImage: "wand.and.stars")
                Spacer()
                Text(stand.map { s in s.modus == "api" ? (s.apiModelle.first(where: { m in m.id == s.apiModell })?.name ?? s.apiModell)
                                                       : ((s.lokalModell as NSString).lastPathComponent) } ?? "…")
                    .foregroundStyle(Farbe.text2).lineLimit(1)
            }
        }
        .task(id: v.zustand) { if v.zustand == .verbunden { stand = try? await v.anfrage("/api/handy/regie", zeit: 30) } }
        .sheet(isPresented: $offen) { RegieWahl(stand: $stand) }
    }
}

// MARK: - Date-Video

struct DateVideoBlatt: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    let c: Charakter
    var ort: String?
    @State private var anweisung = ""
    @State private var sekunden = 20.0
    @State private var arbeitet = false
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. Am Strand bei Sonnenuntergang, wir laufen barfuß und sie zieht mich ins Wasser", text: $anweisung, axis: .vertical)
                        .lineLimit(3...6)
                } header: { Text("Regie (optional)") } footer: {
                    Label(art, systemImage: "sparkles").foregroundStyle(Farbe.rose)
                }
                Section {
                    VStack(alignment: .leading) {
                        Text("Länge: \(Int(sekunden)) Sekunden")
                        Slider(value: $sekunden, in: 10...30, step: 5).tint(Farbe.rose)
                    }
                } footer: {
                    Text("Ihr beide im Video: ihre Referenzbilder und deine Profilfotos. Je 5 Sekunden eine Szene, nahtlos aneinander – dauert einige Minuten. Den Fortschritt siehst du im Chat.")
                }
                if let fehler { Section { Text(fehler).foregroundStyle(.orange) } }
                Section {
                    Button { Task { await los() } } label: {
                        Label(arbeitet ? "Startet …" : "Video drehen", systemImage: "film.stack").frame(maxWidth: .infinity)
                    }.buttonStyle(HauptKnopf()).disabled(arbeitet).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Hintergrund())
            .navigationTitle("Date-Video mit \(c.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { schliessen() } } }
        }
    }

    private var art: String {
        let t = anweisung.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "Automatisch: die Regie erfindet ein passendes Date" + (ort.map { " (\($0))" } ?? "") }
        return t.split(separator: " ").count <= 3 ? "Nur ein Ort: das Date dort wird automatisch erfunden" : "Genau nach deiner Regie"
    }

    @MainActor private func los() async {
        arbeitet = true; defer { arbeitet = false }
        struct K: Encodable { let anweisung: String; let sekunden: Int }
        struct A: Decodable {}
        do {
            _ = try await v.roh("/api/charaktere/\(c.id)/datevideo", methode: "POST",
                                body: K(anweisung: anweisung.trimmingCharacters(in: .whitespacesAndNewlines), sekunden: Int(sekunden)))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            schliessen()
        } catch { fehler = error.localizedDescription }
    }
}

// MARK: - Alle Einstellungen vom iPhone aus (/api/handy/einstellungen)

@MainActor
@Observable
final class HandyEinstellungen {
    var e: [String: Any] = [:]
    var videoModelle: [String: String] = [:]
    var geladen = false

    func laden(_ v: Verbindung) async {
        guard let d = try? await v.roh("/api/handy/einstellungen"),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        e = j["einstellungen"] as? [String: Any] ?? [:]
        videoModelle = j["video_modelle"] as? [String: String] ?? [:]
        geladen = true
    }

    func wert<T>(_ pfad: String, _ standard: T) -> T {
        let teile = pfad.split(separator: ".").map(String.init)
        var o: Any? = e
        for t in teile { o = (o as? [String: Any])?[t] }
        return o as? T ?? standard
    }

    /// Ändern: lokal sofort, dann an den PC (nur der geänderte Zweig).
    func setzen(_ pfad: String, _ neu: Any, _ v: Verbindung) {
        let teile = pfad.split(separator: ".").map(String.init)
        var aenderung: [String: Any] = [teile.last!: neu]
        for t in teile.dropLast().reversed() { aenderung = [t: aenderung] }
        e = Self.verschmelzen(e, aenderung)
        Task {
            guard let d = try? JSONSerialization.data(withJSONObject: aenderung) else { return }
            _ = try? await v.roh("/api/handy/einstellungen", methode: "PUT", rohJSON: d)
        }
    }

    static func verschmelzen(_ a: [String: Any], _ b: [String: Any]) -> [String: Any] {
        var out = a
        for (k, w) in b {
            if let wd = w as? [String: Any], let ad = out[k] as? [String: Any] { out[k] = verschmelzen(ad, wd) } else { out[k] = w }
        }
        return out
    }
}

struct AlleEinstellungen: View {
    @Environment(Verbindung.self) private var v
    @State private var h = HandyEinstellungen()

    var body: some View {
        Group {
            if h.geladen { inhalt } else { Section { ProgressView() } }
        }
        .task(id: v.zustand) { if v.zustand == .verbunden { await h.laden(v) } }
    }

    private func bindung<T>(_ pfad: String, _ standard: T) -> Binding<T> {
        Binding(get: { h.wert(pfad, standard) }, set: { h.setzen(pfad, $0, v) })
    }

    @ViewBuilder private var inhalt: some View {
        Section { TankKarte() } header: { Label("Swipe-Tank", systemImage: "flame.fill") }
        Section {
            Picker("Realismus", selection: bindung("realismus", "natuerlich")) {
                Text("Sofort").tag("sofort"); Text("Natürlich").tag("natuerlich"); Text("Echt").tag("echt")
            }
            Picker("Beziehungstempo", selection: bindung("beziehungstempo", "ausgewogen")) {
                Text("Langsam").tag("langsam"); Text("Ausgewogen").tag("ausgewogen"); Text("Schnell").tag("schnell")
            }
            Toggle("Sie schreibt von sich aus", isOn: bindung("initiative", true))
            Toggle("Anrufe von ihr", isOn: bindung("anrufe_von_ihr", true))
            Toggle("Storys", isOn: bindung("storys", true))
            Toggle("Websuche (Fakten nachschlagen)", isOn: bindung("websuche", true))
            HStack {
                Text("Ruhezeit")
                Spacer()
                TextField("23:00", text: bindung("ruhezeit.von", "23:00")).frame(width: 60).multilineTextAlignment(.center)
                Text("–")
                TextField("08:00", text: bindung("ruhezeit.bis", "08:00")).frame(width: 60).multilineTextAlignment(.center)
            }
        } header: { Text("Verhalten") }
        Section {
            Toggle("Sie darf Fotos schicken", isOn: bindung("bilder_aktiv", true))
            Picker("Fotoqualität", selection: bindung("bild.qualitaet", "maximum")) {
                Text("Blitz").tag("blitz"); Text("Schnell").tag("schnell"); Text("Ausgewogen").tag("ausgewogen"); Text("Max").tag("maximum")
            }.pickerStyle(.segmented)
            if h.wert("bild.qualitaet", "maximum") == "blitz" {
                Text("Wie eine Bild-SMS: in wenigen Sekunden da – kleiner, ohne Bild-Agent und ohne Prüfrunde.")
                    .font(.footnote).foregroundStyle(Farbe.text2)
            }
            Toggle("Fotoprüfung (Hände, Körper, Gesicht)", isOn: bindung("bild.qualitaetspruefung", true))
            Toggle("Handy-Look", isOn: bindung("bild.handylook", true))
        } header: { Text("Fotos") }
        Section {
            Picker("Standard-Videomodell", selection: bindung("video.modell", "wan")) {
                Text("Wan 2.2 (Bewegung)").tag("wan"); Text("LTX 2.5 (mit Ton)").tag("ltx")
            }
            Picker("Videoqualität", selection: bindung("video.qualitaet", "ausgewogen")) {
                Text("Schnell").tag("schnell"); Text("Ausgewogen").tag("ausgewogen"); Text("Maximum").tag("maximum")
            }.pickerStyle(.segmented)
        } header: { Text("Videos") } footer: {
            Text(h.wert("video.qualitaet", "ausgewogen") == "maximum" ? "Höhere Auflösung, mehr Schritte – schönste Videos, dauert am längsten."
                 : h.wert("video.qualitaet", "ausgewogen") == "schnell" ? "Kleiner und ohne Zwischenbilder – am schnellsten." : "Standard-Auflösung, flüssig interpoliert.")
            + Text(" Die Regie darf je Video abweichen (z. B. LTX, wenn sie spricht).")
        }
        Section {
            Toggle("Ausdrucksstarke Stimme (Sprachnachrichten)", isOn: Binding(
                get: { h.wert("stimme.engine", "qwen") == "fish" }, set: { h.setzen("stimme.engine", $0 ? "fish" : "qwen", v) }))
            Toggle("Echte Bewegungen im Videoanruf", isOn: bindung("anrufclips", true))
        } header: { Text("Stimme & Anrufe") }
        Section {
            Toggle("Mitteilungen", isOn: bindung("push.an", true))
            Toggle("Neue Nachrichten", isOn: bindung("push.nachrichten", true))
            Toggle("Sie ruft an", isOn: bindung("push.anrufe", true))
            Toggle("Text auf dem Sperrbildschirm", isOn: bindung("push.vorschau", true))
        } header: { Text("Mitteilungen") } footer: { Text("Kommen nur, wenn die App gerade nicht verbunden ist.") }
    }
}
