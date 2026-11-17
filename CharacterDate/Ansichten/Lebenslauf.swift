import SwiftUI

/// Ihr Leben über die Zeit: Alter, Kapitel (ablehnbar), Ziele, Kalender, Umfeld und Veränderungen – wie am PC im Editor.
struct LebenslaufBlatt: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    let c: Charakter
    @State private var l: Leben?
    @State private var laeuft = false
    @State private var ablehnen: Leben.Kapitel?

    struct Leben: Decodable {
        struct Jetzt: Decodable { let was: String; let ort: String; let verfuegbar: String }
        struct Kapitel: Decodable, Identifiable { let id: String; let zeit: Double; let titel: String; let notiz: String; let themen: [String]?; let abgelehnt: Bool }
        struct Ziel: Decodable, Identifiable { let id: String; let was: String; let fortschritt: Double; let notiz: String?; let fertig: Bool? }
        struct Termin: Decodable, Identifiable { let id: String; let was: String; let ort: String?; let von: Double; let bis: Double; let verfuegbar: String? }
        struct Figur: Decodable, Hashable { let name: String; let beschreibung: String? }
        struct Drift: Decodable, Hashable { let zeit: Double; let satz: String? }
        struct Look: Decodable, Hashable { let zeit: Double; let notiz: String? }
        let alter: Int?
        let geburtstag: String?
        let jetzt: Jetzt
        let kapitel: [Kapitel]
        let ziele: [Ziel]
        let kalender: [Termin]
        let umfeld: [Figur]
        let drift: [Drift]
        let look: [Look]
        let jahreszeit: String
        let wetter: String
    }

    private static let erreichbar = ["ja": "erreichbar", "kurz": "kaum erreichbar", "nein": "nicht erreichbar"]
    private func datum(_ t: Double) -> String {
        Date(timeIntervalSince1970: t).formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "de_DE")))
    }
    private func tag(_ t: Double) -> String {
        Date(timeIntervalSince1970: t).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
    }

    var body: some View {
        NavigationStack {
            List {
                if let l {
                    Section {
                        if let a = l.alter { LabeledContent("Alter", value: "\(a) Jahre" + (l.geburtstag.map { " · Geburtstag \($0)" } ?? "")) }
                        LabeledContent("Wetter", value: "\(l.jahreszeit) · \(l.wetter)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gerade: \(l.jetzt.was)")
                            Text(Self.erreichbar[l.jetzt.verfuegbar] ?? l.jetzt.verfuegbar).font(.caption).foregroundStyle(Farbe.text2)
                        }
                    }
                    Section {
                        if l.kapitel.isEmpty { Text("Noch kein Kapitel – das erste kommt nach einigen Wochen.").font(.footnote).foregroundStyle(Farbe.text2) }
                        ForEach(l.kapitel) { k in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(k.titel).bold(); Spacer(); Text(datum(k.zeit)).font(.caption).foregroundStyle(Farbe.text2) }
                                Text(k.notiz).font(.subheadline)
                                if let t = k.themen, !t.isEmpty { Text("Beschäftigt sie: " + t.joined(separator: ", ")).font(.caption).foregroundStyle(Farbe.text2) }
                                if k.abgelehnt { Text("abgelehnt").font(.caption).foregroundStyle(Farbe.text3) }
                            }
                            .opacity(k.abgelehnt ? 0.5 : 1)
                            .swipeActions { if !k.abgelehnt { Button("Ablehnen", role: .destructive) { ablehnen = k } } }
                        }
                    } header: { Text("Lebenskapitel") } footer: { Text("Nach links wischen, um ein Kapitel abzulehnen.") }
                    Section("Ziele") {
                        if l.ziele.isEmpty { Text("Noch keine Ziele.").font(.footnote).foregroundStyle(Farbe.text2) }
                        ForEach(l.ziele) { z in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(z.was).bold(); Spacer(); Text(z.fertig == true ? "erreicht 🎉" : "\(Int(z.fortschritt)) %").font(.caption) }
                                ProgressView(value: min(100, z.fortschritt), total: 100).tint(Farbe.rose)
                                if let n = z.notiz, !n.isEmpty { Text(n).font(.caption).foregroundStyle(Farbe.text2) }
                            }
                        }
                    }
                    Section("Kalender") {
                        if l.kalender.isEmpty { Text("Keine Termine geplant.").font(.footnote).foregroundStyle(Farbe.text2) }
                        ForEach(l.kalender) { t in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tag(t.von) + (t.bis - t.von > 86400 ? " – " + tag(t.bis) : "")).font(.caption.bold())
                                Text(t.was + ((t.ort ?? "").isEmpty ? "" : " · \(t.ort!)")).font(.subheadline)
                                if let e = t.verfuegbar { Text(Self.erreichbar[e] ?? e).font(.caption2).foregroundStyle(Farbe.text2) }
                            }
                        }
                    }
                    Section("Umfeld") {
                        if l.umfeld.isEmpty { Text("Noch keine festen Nebenfiguren.").font(.footnote).foregroundStyle(Farbe.text2) }
                        ForEach(l.umfeld, id: \.self) { f in
                            VStack(alignment: .leading, spacing: 2) { Text(f.name).bold(); if let b = f.beschreibung { Text(b).font(.caption).foregroundStyle(Farbe.text2) } }
                        }
                    }
                    if !l.drift.isEmpty || !l.look.isEmpty {
                        Section("Veränderungen") {
                            ForEach(l.drift, id: \.self) { d in Text(d.satz ?? "").font(.subheadline) }
                            ForEach(l.look, id: \.self) { d in Text("Neuer Look: " + (d.notiz ?? "")).font(.subheadline) }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Hintergrund())
            .navigationTitle("Lebenslauf von \(c.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { schliessen() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await weiter() } } label: { if laeuft { ProgressView() } else { Image(systemName: "wand.and.stars") } }
                        .disabled(laeuft).accessibilityLabel("Leben weiterdrehen")
                }
            }
            .confirmationDialog("Kapitel »\(ablehnen?.titel ?? "")« ablehnen?", isPresented: Binding(get: { ablehnen != nil }, set: { if !$0 { ablehnen = nil } }),
                                titleVisibility: .visible) {
                Button("Ablehnen", role: .destructive) {
                    if let k = ablehnen { Task { l = try? await v.anfrage("/api/charaktere/\(c.id)/kapitel/\(k.id)/ablehnen", methode: "POST") } }
                }
            } message: { Text("Die geänderten Angaben bekommen ihre alten Werte zurück.") }
            .task { l = try? await v.anfrage("/api/charaktere/\(c.id)/leben") }
        }
    }

    @MainActor private func weiter() async {
        laeuft = true
        defer { laeuft = false }
        if let n: Leben = try? await v.anfrage("/api/charaktere/\(c.id)/leben/weiter", methode: "POST", zeit: 600) {
            l = n
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
