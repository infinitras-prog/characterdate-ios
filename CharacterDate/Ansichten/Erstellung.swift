import SwiftUI
import Observation

/// Was gerade entsteht (Foto/Video): Schritt, Prozent, Restzeit – vom PC gemeldet (Ereignis »erstellung«).
@MainActor
@Observable
final class Erstellungen {
    static let shared = Erstellungen()
    struct Stand: Equatable { var schritt: String; var prozent: Int; var rest: Double?; var seit: Double; var empfangen: Date
        var prompt: String = ""; var vorschau: Bool = false }
    var staende: [String: Stand] = [:]
    /// Neu erzeugte Fotos (Kandidaten) je ursprünglicher Bild-ID: (id, url) oder Fehlertext.
    var kandidaten: [String: (id: String, url: String)] = [:]
    var kandidatFehler: [String: String] = [:]
    @ObservationIgnored private var abo: UUID?

    func starten(_ v: Verbindung) {
        guard abo == nil else { return }
        abo = v.abonnieren { [weak self] e in
            Task { @MainActor in self?.ereignis(e) }
        }
        Task { await nachladen(v) }
    }

    func nachladen(_ v: Verbindung) async {
        guard let d = try? await v.roh("/api/erstellung"),
              let l = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return }
        for e in l { uebernehmen(e) }
    }

    private func uebernehmen(_ e: [String: Any]) {
        guard let nid = e["nachricht_id"] as? String else { return }
        staende[nid] = Stand(schritt: e["schritt"] as? String ?? "", prozent: (e["prozent"] as? NSNumber)?.intValue ?? 0,
                             rest: (e["rest"] as? NSNumber)?.doubleValue, seit: (e["seit"] as? NSNumber)?.doubleValue ?? 0,
                             empfangen: Date(), prompt: e["prompt"] as? String ?? "",
                             vorschau: e["vorschau"] as? Bool ?? false)
    }

    private func ereignis(_ e: Verbindung.Ereignis) {
        switch e.typ {
        case "erstellung": uebernehmen(e.roh)
        case "aktualisiert": if let n = e.nachricht { staende[n.id] = nil }
        case "bild_neu":
            guard let bid = e.roh["bild_id"] as? String else { return }
            staende["neu-" + bid] = nil
            if let k = e.roh["kandidat"] as? [String: Any], let id = k["id"] as? String, let url = k["url"] as? String {
                kandidaten[bid] = (id, url)
            } else if let f = e.roh["fehler"] as? String { kandidatFehler[bid] = f }
        default: break
        }
    }
}

/// Platzhalter, solange ein Foto/Video entsteht: drehender Farbverlauf, Fortschrittsring, Schritt, Restzeit.
struct ErstellungsKarte: View {
    @Environment(Verbindung.self) private var v
    let nid: String
    var titel: String
    var symbol: String = "camera.fill"
    var breite: CGFloat = 230
    private var lager: Erstellungen { Erstellungen.shared }
    @State private var vorschau = false
    @State private var fragen = false
    @State private var stoppt = false
    @State private var promptOffen = false

    var body: some View {
        let s = lager.staende[nid]
        let p = Double(s?.prozent ?? 0) / 100
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { t in
            let winkel = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 9) / 9 * 360
            let alter = s.map { t.date.timeIntervalSince($0.empfangen) } ?? 0
            ZStack {
                AngularGradient(colors: [Color(red: 0.64, green: 0.42, blue: 0.98), Farbe.rose,
                                         Color(red: 0.96, green: 0.72, blue: 0.38), Farbe.mint, Color(red: 0.64, green: 0.42, blue: 0.98)],
                                center: .center, angle: .degrees(winkel))
                    .scaleEffect(1.8).blur(radius: 34).opacity(0.85)
                VStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles").font(.caption2)
                        Text(titel.uppercased()).font(.caption2.weight(.semibold)).tracking(1).lineLimit(1)
                        Spacer()
                        Button { withAnimation(.spring(duration: 0.35)) { vorschau.toggle() } } label: {
                            Image(systemName: vorschau ? "eye.slash" : "eye").font(.caption.bold())
                                .frame(width: 26, height: 26).background(.black.opacity(0.35), in: Circle())
                        }.accessibilityLabel("Live-Vorschau")
                        Button { fragen = true } label: {
                            Image(systemName: "xmark").font(.caption.bold())
                                .frame(width: 26, height: 26).background(.black.opacity(0.35), in: Circle())
                        }.disabled(stoppt).accessibilityLabel("Abbrechen")
                    }.foregroundStyle(.white.opacity(0.85))
                    if vorschau { LiveVorschau(nid: nid).transition(.opacity.combined(with: .scale(scale: 0.95))) }
                    ZStack {
                        // dunkle Scheibe: Herzen fliegen nie über die Zahl
                        Circle().fill(Color(red: 0.055, green: 0.043, blue: 0.086).opacity(0.96)).padding(6)
                        Circle().stroke(.white.opacity(0.1), lineWidth: 7)
                        Circle().trim(from: 0, to: max(0.01, p))
                            .stroke(AngularGradient(colors: [Color(red: 0.64, green: 0.42, blue: 0.98), Farbe.rose,
                                                             Color(red: 0.96, green: 0.72, blue: 0.38)], center: .center),
                                    style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Farbe.rose.opacity(0.6), radius: 8)
                            .animation(.spring(duration: 0.8), value: p)
                        VStack(spacing: 2) {
                            Image(systemName: symbol).font(.system(size: 17))
                                .scaleEffect(1 + 0.08 * sin(t.date.timeIntervalSinceReferenceDate * 3.4))
                            Text("\(s?.prozent ?? 0)%").font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText())
                        }.foregroundStyle(.white)
                    }
                    .frame(width: 110, height: 110)
                    Text(s?.schritt.isEmpty == false ? s!.schritt : "Wird vorbereitet")
                        .font(.footnote.weight(.medium)).multilineTextAlignment(.center).foregroundStyle(.white)
                        .frame(minHeight: 34).id(s?.schritt ?? "")
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
                        .animation(.easeOut(duration: 0.35), value: s?.schritt)
                    if let pr = s?.prompt, !pr.isEmpty {
                        Text(pr).font(.caption2).foregroundStyle(.white.opacity(0.75))
                            .lineLimit(promptOffen ? nil : 3).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(7).background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                            .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { promptOffen.toggle() } }
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1))
                            Capsule().fill(LinearGradient(colors: [Color(red: 0.64, green: 0.42, blue: 0.98), Farbe.rose,
                                                                   Color(red: 0.96, green: 0.72, blue: 0.38)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: g.size.width * p).shadow(color: Farbe.rose, radius: 6)
                                .animation(.spring(duration: 0.8), value: p)
                        }
                    }.frame(height: 4)
                    HStack {
                        Text(s?.rest.map { "noch ca. " + Self.zeit(max(1, $0 - alter)) } ?? "Zeit wird geschätzt …")
                        Spacer()
                        if let s { Text(Self.zeit(s.seit + alter)) }
                    }
                    .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
                }
                .padding(14)
                .background { Herzen(prozent: p, zeit: t.date.timeIntervalSinceReferenceDate) }
                .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(9)
            }
        }
        .frame(width: breite)
        .frame(minHeight: breite * 4 / 3)
        .confirmationDialog("Erstellung abbrechen?", isPresented: $fragen, titleVisibility: .visible) {
            Button("Abbrechen", role: .destructive) {
                stoppt = true
                Task { _ = try? await v.roh("/api/erstellung/\(nid)/abbrechen", methode: "POST") }
            }
            Button("Weiterlaufen lassen", role: .cancel) {}
        } message: { Text("Was bisher entstanden ist, wird verworfen. Du kannst es danach neu starten.") }
        .background(Color(red: 0.08, green: 0.07, blue: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color(red: 0.64, green: 0.42, blue: 0.98).opacity(0.25), radius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titel): \(s?.schritt ?? "wird vorbereitet"), \(s?.prozent ?? 0) Prozent")
    }

    /// Herzen steigen auf – je mehr Prozent, desto mehr (in den App-Farben).
    struct Herzen: View {
        let prozent: Double
        let zeit: Double
        static let farben: [Color] = [Farbe.rose, Farbe.violett, Color(red: 0.96, green: 0.72, blue: 0.38),
                                       Color(red: 1, green: 0.56, blue: 0.78), Color(red: 0.78, green: 0.61, blue: 1)]
        var body: some View {
            Canvas { ctx, size in
                let n = min(30, 3 + Int((prozent * 27).rounded()))
                for i in 0..<n {
                    func z(_ k: Double) -> Double { let x = sin(Double(i + 1) * 9301 + k * 49297) * 233280; return x - floor(x) }
                    let dauer = 4.5 + z(3) * 4.5
                    let phase = ((zeit + z(4) * 8).truncatingRemainder(dividingBy: dauer)) / dauer
                    let groesse = 9 + z(2) * 14
                    let x = size.width * (0.05 + z(1) * 0.9) + sin(phase * .pi * 2) * (8 + z(5) * 14)
                    let y = size.height + 20 - phase * (size.height + 50)
                    let alpha = phase < 0.12 ? phase / 0.12 : phase > 0.85 ? (1 - phase) / 0.15 : 1
                    var c = ctx
                    c.opacity = alpha * 0.85
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .degrees((z(6) - 0.5) * 50 * cos(phase * .pi)))
                    var bild = c.resolve(Image(systemName: "heart.fill"))
                    bild.shading = .color(Self.farben[i % Self.farben.count])
                    c.draw(bild, in: CGRect(x: -groesse / 2, y: -groesse / 2, width: groesse, height: groesse))
                }
            }
            .allowsHitTesting(false)
        }
    }

    static func zeit(_ s: Double) -> String {
        s >= 60 ? String(format: "%d:%02d min", Int(s) / 60, Int(s) % 60) : "\(max(1, Int(s.rounded()))) s"
    }
}


/// Live-Vorschau: neuestes Zwischenbild der Engine, alle 1,5 s neu geholt.
struct LiveVorschau: View {
    @Environment(Verbindung.self) private var v
    let nid: String
    @State private var bild: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.35))
            if let bild {
                Image(uiImage: bild).resizable().scaledToFill()
            } else {
                Text("Noch kein Zwischenbild …").font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            while !Task.isCancelled {
                if let d = try? await v.roh("/api/erstellung/\(nid)/vorschau", zeit: 10), let b = UIImage(data: d) {
                    withAnimation(.easeOut(duration: 0.3)) { bild = b }
                }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}
