import SwiftUI

// MARK: Storys

struct StoryEintrag: Decodable, Identifiable, Hashable {
    let id: String
    let charId: String
    let url: String
    let text: String
    let ort: String
    let erstellt: Double
    var gesehen: Bool
}

@Observable
final class StoryLager {
    var storys: [String: [StoryEintrag]] = [:]

    @MainActor
    func laden(_ v: Verbindung) async {
        if let s: [String: [StoryEintrag]] = try? await v.anfrage("/api/storys") { storys = s }
    }
    func neu(_ cid: String) -> Bool { storys[cid]?.contains { !$0.gesehen } ?? false }
}

/// Profilbild mit Story-Ring (bunt = neu, grau = gesehen).
struct StoryRing<Inhalt: View>: View {
    let hat: Bool
    let neu: Bool
    @ViewBuilder let inhalt: () -> Inhalt
    var body: some View {
        if hat {
            inhalt()
                .padding(3)
                .overlay(Circle().stroke(neu ? AnyShapeStyle(AngularGradient(colors: [Farbe.rose, Farbe.violett, .orange, Farbe.rose], center: .center))
                                             : AnyShapeStyle(Color.white.opacity(0.25)), lineWidth: 2.5))
        } else {
            inhalt()
        }
    }
}

struct StoryBetrachter: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    let c: Charakter
    @State var storys: [StoryEintrag]
    let gesehen: (String) -> Void
    @State private var i = 0
    @State private var fort: Double = 0
    @State private var bilder: [String: UIImage] = [:]

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if i < storys.count, let b = bilder[storys[i].url] {
                // Bild füllt den Bildschirm, ohne die Ansicht breiter zu machen (sonst werden Name und Text abgeschnitten)
                Color.clear.ignoresSafeArea()
                    .overlay { Image(uiImage: b).resizable().scaledToFill().ignoresSafeArea() }
                    .clipped()
                    .id(storys[i].id).transition(.opacity)
            } else {
                ProgressView().tint(.white).frame(maxHeight: .infinity)
            }
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { if i > 0 { i -= 1; fort = 0 } }
                Color.clear.contentShape(Rectangle()).onTapGesture { weiter() }
            }
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(storys.indices, id: \.self) { k in
                        GeometryReader { g in
                            Capsule().fill(.white.opacity(0.3))
                                .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: g.size.width * (k < i ? 1 : k == i ? fort : 0)) }
                        }.frame(height: 3)
                    }
                }
                HStack(spacing: 8) {
                    Avatar(c: c, groesse: 32)
                    Text(c.name).font(.subheadline.bold()).lineLimit(1)
                    if i < storys.count { Text("\(uhrzeit(storys[i].erstellt)) · \(storys[i].ort)").font(.caption).opacity(0.75).lineLimit(1) }
                    Spacer()
                    Button { schliessen() } label: { Image(systemName: "xmark").font(.title3) }
                }
                Spacer()
                if i < storys.count, !storys[i].text.isEmpty {
                    Text(storys[i].text).font(.body).multilineTextAlignment(.center).padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14)).padding(.bottom, 30)
                }
            }
            .foregroundStyle(.white).padding(.horizontal, 12).padding(.top, 8)
        }
        .task {
            i = storys.firstIndex { !$0.gesehen } ?? 0
            for s in storys { if let d = try? await v.medien(s.url), let b = UIImage(data: d) { bilder[s.url] = b } }
        }
        .task(id: i) {
            guard i < storys.count else { return }
            if !storys[i].gesehen {
                storys[i].gesehen = true; gesehen(storys[i].id)
                struct Ok: Decodable { let ok: Bool }
                let _: Ok? = try? await v.anfrage("/api/storys/\(storys[i].id)/gesehen", methode: "POST")
            }
            fort = 0
            let schritte = 120
            for _ in 0..<schritte {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
                fort += 1.0 / Double(schritte)
            }
            weiter()
        }
    }

    private func weiter() { if i < storys.count - 1 { i += 1; fort = 0 } else { schliessen() } }
}

// MARK: Dates

struct DateOrt: Decodable, Identifiable, Hashable { let id: String; let name: String; let emoji: String; let szene: String }
struct DateInfo: Decodable, Hashable { let ort: String; let szene: String; let emoji: String; let start: Double }

struct DateWahl: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    let c: Charakter
    let gestartet: (DateInfo) -> Void
    @State private var orte: [DateOrt] = []
    @State private var eigen = ""
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Wohin geht ihr?") {
                    ForEach(orte) { o in
                        Button { Task { await los(o.id) } } label: { Text(o.emoji + "  " + o.name) }
                    }
                }
                Section("Eigener Ort") {
                    TextField("z. B. Eislaufen am Rathausplatz", text: $eigen).submitLabel(.go).onSubmit { Task { await los(eigen) } }
                    Button("Los geht's") { Task { await los(eigen) } }.disabled(eigen.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let fehler { Text(fehler).foregroundStyle(Farbe.rose) }
            }
            .scrollContentBackground(.hidden)
            .background(Hintergrund())
            .navigationTitle("Date mit \(c.name)")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { schliessen() } } }
            .task { orte = (try? await v.anfrage("/api/dates/orte")) ?? [] }
        }
    }

    @MainActor
    private func los(_ ort: String) async {
        let o = ort.trimmingCharacters(in: .whitespaces)
        guard !o.isEmpty else { return }
        struct Antwort: Decodable { let date: DateInfo }
        struct Koerper: Encodable { let ort: String }
        do {
            let a: Antwort = try await v.anfrage("/api/charaktere/\(c.id)/date", methode: "POST", body: Koerper(ort: o))
            gestartet(a.date); schliessen()
        } catch { fehler = error.localizedDescription }
    }
}
