import SwiftUI

/// Referenzstimme am iPhone nachträglich bearbeiten: Ausschnitt aus der Original-Probe (bis 30 s) und gesprochenen Text.
struct StimmeBearbeiten: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    let c: Charakter
    @State private var von: Double = 0
    @State private var bis: Double = 30
    @State private var text = ""
    @State private var arbeitet = false
    @State private var meldung: String?

    private var st: StimmeInfo { c.dna.stimme ?? StimmeInfo() }
    private var gesamt: Double { max(3, st.originalDauer ?? st.bis ?? 30) }

    var body: some View {
        NavigationStack {
            Form {
                if let o = st.original {
                    Section {
                        SprachBlase(pfad: o, dauer: gesamt)
                        VStack(alignment: .leading) {
                            Text("Start \(zeit(von))").font(.caption)
                            Slider(value: $von, in: 0...gesamt, step: 0.1, onEditingChanged: { _ in if bis - von < 3 { von = max(0, bis - 3) }; if bis - von > 30 { bis = von + 30 } })
                            Text("Ende \(zeit(bis))").font(.caption)
                            Slider(value: $bis, in: 0...gesamt, step: 0.1, onEditingChanged: { _ in if bis - von < 3 { bis = min(gesamt, von + 3) }; if bis - von > 30 { von = bis - 30 } })
                        }
                        Text("Ausschnitt: \(String(format: "%.1f", bis - von)) s").font(.footnote)
                            .foregroundStyle(bis - von > 30 || bis - von < 3 ? Farbe.rose : Farbe.text3)
                    } header: { Text("Ausschnitt aus der Original-Probe") } footer: {
                        Text("Wähl den Teil mit der klarsten Sprache – höchstens 30 Sekunden.")
                    }
                } else {
                    Section { Text("Für diese Stimme gibt es keine längere Original-Probe. Du kannst den Text korrigieren oder eine neue Probe hochladen.").font(.footnote) }
                }
                Section {
                    TextField("Was in der Referenz gesagt wird …", text: $text, axis: .vertical).lineLimit(3...6)
                    Button("Text neu erkennen") { Task { await senden(["text_neu_erkennen": true]) } }.disabled(arbeitet)
                } header: { Text("Gesprochener Text") } footer: {
                    Text("Stimmt er Wort für Wort, wird die Stimme genauer kopiert.")
                }
                if let meldung { Section { Text(meldung).font(.footnote) } }
            }
            .scrollContentBackground(.hidden)
            .background(Hintergrund())
            .navigationTitle("Stimme bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { schliessen() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(arbeitet ? "…" : "Übernehmen") {
                        let geaendert = abs(von - (st.von ?? 0)) > 0.05 || abs(bis - (st.bis ?? gesamt)) > 0.05
                        Task { await senden(geaendert && st.original != nil ? ["von": von, "bis": bis] : ["ref_text": text]) }
                    }.disabled(arbeitet)
                }
            }
            .onAppear { von = st.von ?? 0; bis = min(gesamt, st.bis ?? min(30, gesamt)); text = st.refText ?? "" }
        }
    }

    private func zeit(_ x: Double) -> String { String(format: "%d:%04.1f", Int(x) / 60, x.truncatingRemainder(dividingBy: 60)) }

    @MainActor
    private func senden(_ d: [String: Any]) async {
        arbeitet = true; meldung = nil
        defer { arbeitet = false }
        struct Koerper: Encodable {
            let von: Double?; let bis: Double?; let ref_text: String?; let text_neu_erkennen: Bool?
        }
        let k = Koerper(von: d["von"] as? Double, bis: d["bis"] as? Double, ref_text: d["ref_text"] as? String,
                        text_neu_erkennen: d["text_neu_erkennen"] as? Bool)
        do {
            let neu: Charakter = try await v.anfrage("/api/charaktere/\(c.id)/stimme", methode: "PUT", body: k, zeit: 180)
            text = neu.dna.stimme?.refText ?? text
            await v.neuLaden()
            meldung = "Übernommen."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch { meldung = error.localizedDescription }
    }
}
