import SwiftUI
import AudioToolbox

struct HauptAnsicht: View {
    @Environment(Verbindung.self) private var v
    @State private var tab = 0
    @State private var chatMit: Charakter?
    @State private var ruft: Klingeln?
    @State private var angenommen: Klingeln?
    @State private var abo: UUID?
    @State private var widgetUhr: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if case .offline(let grund) = v.zustand {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                    Text(grund).font(.caption).lineLimit(2)
                    Spacer()
                    Button("Erneut") { Task { await v.verbinden() } }.font(.caption.bold())
                }
                .padding(10).background(Color.orange.opacity(0.18)).foregroundStyle(.orange)
            }
            TabView(selection: $tab) {
                NavigationStack { HomeAnsicht(oeffnen: { c in chatMit = c; tab = 1 }) }
                    .tabItem { Label("Home", systemImage: "house") }.tag(0)
                NavigationStack { ChatListe(auswahl: $chatMit) }
                    .tabItem { Label("Chats", systemImage: "bubble.left") }.tag(1)
                NavigationStack { SwipeAnsicht(chatOeffnen: { c in chatMit = c; tab = 1 }) }
                    .tabItem { Label("Swipe", systemImage: "flame") }.tag(5)
                LumigramAnsicht(chatOeffnen: { c in chatMit = c; tab = 1 }, zurueck: { tab = 0 }, zuChats: { tab = 1 })
                    .tabItem { Label("Lumigram", systemImage: "camera.aperture") }.tag(6)
                NavigationStack { ErstellenAnsicht(fertig: { c in chatMit = c; tab = 1 }) }
                    .tabItem { Label("Char erstellen", systemImage: "plus.circle") }.tag(2)
                NavigationStack { GalerieAnsicht() }
                    .tabItem { Label("Galerie", systemImage: "photo") }.tag(3)
                NavigationStack { EinstellungenAnsicht() }
                    .tabItem { Label("Einstellungen", systemImage: "gearshape") }.tag(4)
            }
        }
        .onAppear {
            abo = v.abonnieren { e in
                if e.typ == "eingehender_anruf", let cid = e.charId, let c = v.charaktere.first(where: { $0.id == cid }) {
                    ruft = Klingeln(c: c, video: e.roh["video"] as? Bool ?? false)
                }
                if e.typ == "anruf_ende", ruft?.c.id == e.charId { ruft = nil }
                if e.typ == "nachricht" {
                    widgetUhr?.cancel()
                    widgetUhr = Task { try? await Task.sleep(for: .seconds(4)); await v.neuLaden(); await WidgetSchreiber.aktualisieren(v) }
                }
            }
            Push.shared.anmeldenWennMoeglich = { Task { await Push.shared.anmelden(v) } }
        }
        .overlay(alignment: .bottomTrailing) {
            // Chip-Knopf (Sprachmodell) unten rechts über der Tab-Leiste – stört dort keine Überschriften/Bilder.
            // In Swipe und Lumigram liegen unten eigene Knöpfe → dort ausgeblendet.
            if v.zustand == .verbunden && chatMit == nil && tab != 5 && tab != 6 {
                RegieKnopf().padding(.trailing, 16).padding(.bottom, 96)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .task(id: v.zustand) {
            guard v.zustand == .verbunden else { return }
            Erstellungen.shared.starten(v)
            await Erstellungen.shared.nachladen(v)
            await klingeltPruefen()
            zielAbarbeiten()
            await Push.shared.einrichten()
            await Push.shared.anmelden(v)
            await WidgetSchreiber.aktualisieren(v)
        }
        .onChange(of: Push.shared.ziel) { _, _ in zielAbarbeiten() }
        .onDisappear { if let abo { v.abbestellen(abo) } }
        .fullScreenCover(item: $ruft) { k in
            KlingelAnsicht(k: k) { video in
                ruft = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { angenommen = Klingeln(c: k.c, video: video) }
            } ablehnen: {
                ruft = nil
                Task { struct Ok: Decodable { let ok: Bool }; let _: Ok? = try? await v.anfrage("/api/charaktere/\(k.c.id)/anruf/ablehnen", methode: "POST") }
            }
        }
        .fullScreenCover(item: $angenommen) { k in AnrufAnsicht(c: k.c, video: k.video, eingehend: true) }
    }
}

extension HauptAnsicht {
    private struct KlingeltGerade: Decodable { let charId: String; let video: Bool? }

    /// Gerade erst verbunden (z. B. über die Mitteilung »sie ruft an« geöffnet): klingelt es noch?
    @MainActor
    func klingeltPruefen() async {
        guard ruft == nil, angenommen == nil, !Telefon.laeuft,
              let l: [KlingeltGerade] = try? await v.anfrage("/api/anruf/klingelt"),
              let k = l.first, let c = v.charaktere.first(where: { $0.id == k.charId }) else { return }
        ruft = Klingeln(c: c, video: k.video ?? false)
    }

    /// Angetippte Mitteilung oder Widget: Chat öffnen bzw. Anruf zeigen.
    @MainActor
    func zielAbarbeiten() {
        guard let z = Push.shared.ziel, v.zustand == .verbunden,
              let c = v.charaktere.first(where: { $0.id == z.charId }) else { return }
        Push.shared.ziel = nil
        if z.anruf {
            Task {
                await klingeltPruefen()
                if ruft == nil, angenommen == nil { chatMit = c; tab = 1 }     // schon vorbei → Chat (dort steht »verpasst«)
            }
        } else {
            chatMit = c; tab = 1
        }
    }
}

struct Klingeln: Identifiable { let c: Charakter; let video: Bool; var id: String { c.id + (video ? "v" : "a") } }

/// SIE ruft an: Vollbild mit pulsierendem Bild, Vibration im Klingel-Rhythmus, annehmen/ablehnen.
struct KlingelAnsicht: View {
    @Environment(Verbindung.self) private var v
    let k: Klingeln
    let annehmen: (Bool) -> Void
    let ablehnen: () -> Void
    @State private var puls = false

    var body: some View {
        ZStack {
            Hintergrund().ignoresSafeArea()
            if let a = k.c.avatarUrl { NetzBild(pfad: a).ignoresSafeArea().blur(radius: 40).opacity(0.5).scaleEffect(1.2) }
            VStack(spacing: 18) {
                Spacer()
                Avatar(c: k.c, groesse: 150)
                    .shadow(color: Farbe.rose.opacity(puls ? 0.7 : 0.2), radius: puls ? 30 : 10)
                    .scaleEffect(puls ? 1.04 : 1)
                Text(k.c.name).font(.system(size: 34, weight: .semibold))
                Text(k.video ? "Videoanruf …" : "ruft dich an …").font(.headline).foregroundStyle(Farbe.text2)
                Spacer()
                HStack(spacing: 46) {
                    knopf("phone.down.fill", farbe: .red, text: "Ablehnen") { ablehnen() }
                    knopf("phone.fill", farbe: .green, text: "Annehmen") { annehmen(false) }
                    if k.c.avatarUrl != nil { knopf("video.fill", farbe: .green, text: "Video") { annehmen(true) } }
                }
                .padding(.bottom, 50)
            }
            .foregroundStyle(.white)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { puls = true } }
        .task {
            // Klingel-Rhythmus: zweimal kurz vibrieren, Pause – bis angenommen/abgelehnt
            while !Task.isCancelled {
                for _ in 0..<2 {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    try? await Task.sleep(for: .milliseconds(350))
                }
                if v.iphoneAktiv { AudioServicesPlaySystemSound(1007) }     // am PC aktiv: nur vibrieren
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func knopf(_ symbol: String, farbe: Color, text: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 74, height: 74).background(farbe, in: Circle())
                Text(text).font(.caption).foregroundStyle(Farbe.text2)
            }
        }
    }
}

/// Kopfzeile wie im Entwurf: Herz, Name, Untertitel.
struct Marke: View {
    var body: some View {
        HStack(spacing: 10) {
            Herz(groesse: 30)
            VStack(alignment: .leading, spacing: 1) {
                (Text("Character") + Text("Date").foregroundStyle(Farbe.rose) + Text(" AI").foregroundStyle(Farbe.violett))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Deine KI-Charaktere · Chatten · Daten").font(.caption2).foregroundStyle(Farbe.text3)
            }
            Spacer()
        }
    }
}

struct HomeAnsicht: View {
    @Environment(Verbindung.self) private var v
    let oeffnen: (Charakter) -> Void
    @State private var index = 0

    var fertig: [Charakter] { v.charaktere.filter { ($0.entwurf ?? 0) == 0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Marke()
                VerbindungsLeiste()
                if fertig.isEmpty {
                    VStack(spacing: 12) {
                        Herz(groesse: 54)
                        Text("Erschaffe deinen ersten Charakter").font(.title3.weight(.semibold))
                        Text("Beschreib sie in ein paar Sätzen. Danach lernt ihr euch kennen – erst schreiben, dann Vertrauen, dann Dates.")
                            .font(.subheadline).foregroundStyle(Farbe.text2).multilineTextAlignment(.center)
                    }
                    .padding(26).frame(maxWidth: .infinity).glas()
                } else {
                    HStack {
                        Text("Entdecken").font(.title2.weight(.semibold))
                        Spacer()
                        StatusChip()
                    }
                    TabView(selection: $index) {
                        ForEach(Array(fertig.enumerated()), id: \.element.id) { i, c in
                            HeldKarte(c: c, oeffnen: { oeffnen(c) }).tag(i).padding(.horizontal, 2)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: fertig.count > 1 ? .automatic : .never))
                    .frame(height: 520)
                    HStack {
                        Text("Deine Charaktere").font(.title3.weight(.semibold))
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(fertig) { c in
                                Button { oeffnen(c) } label: { MiniKarte(c: c) }.buttonStyle(.plain)
                                    .scrollTransition(.interactive, axis: .horizontal) { inhalt, phase in
                                        inhalt.scaleEffect(phase.isIdentity ? 1 : 0.88)
                                            .opacity(phase.isIdentity ? 1 : 0.6)
                                            .rotation3DEffect(.degrees(phase.value * -14), axis: (x: 0, y: 1, z: 0))
                                    }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .refreshable { await v.neuLaden() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct VerbindungsLeiste: View {
    @Environment(Verbindung.self) private var v
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer").foregroundStyle(Farbe.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text(v.zustand == .verbunden ? "Verbunden mit \(v.pcName)" : v.zustand == .verbindet ? "Verbinde …" : "Nicht verbunden")
                    .font(.subheadline.weight(.semibold))
                Text("KI läuft auf deinem PC · privat").font(.caption2).foregroundStyle(Farbe.text3)
            }
            Spacer()
            Circle().fill(v.zustand == .verbunden ? Farbe.mint : .orange).frame(width: 9, height: 9)
                .shadow(color: v.zustand == .verbunden ? Farbe.mint : .clear, radius: 5)
        }
        .padding(12).glas(16)
    }
}

struct HeldKarte: View {
    let c: Charakter
    let oeffnen: () -> Void
    @State private var zoom = false
    @State private var da = false
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NetzBild(pfad: c.avatarUrl)
                .scaleEffect(zoom ? 1.08 : 1.0)          // langsamer Ken-Burns-Zoom
                .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: zoom)
            LinearGradient(colors: [.clear, .clear, Farbe.grund.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(c.name).font(.system(size: 32, weight: .semibold, design: .rounded)); Image(systemName: "heart.fill").foregroundStyle(Farbe.rose).symbolEffect(.pulse, options: .repeating) }
                        Text(c.dna.kurzbeschreibung ?? "").font(.subheadline).foregroundStyle(Farbe.text2).lineLimit(2)
                    }
                    Spacer()
                    Ring(wert: c.beziehung.fortschritt ?? 0, oben: "Lv. \(c.beziehung.level)", unten: c.beziehung.levelName, groesse: 78)
                }
                if !c.tags.isEmpty {
                    HStack { ForEach(c.tags, id: \.self) { Chip(text: $0) } }
                }
                HStack(spacing: 6) {
                    Image(systemName: "face.smiling").foregroundStyle(Farbe.mint)
                    Text("Stimmung: ").foregroundStyle(Farbe.text2) + Text(c.beziehung.stimmung).foregroundStyle(Farbe.rose)
                }.font(.subheadline)
                Button(action: oeffnen) {
                    Label("Chat starten", systemImage: "bubble.left.fill").frame(maxWidth: .infinity)
                }.buttonStyle(HauptKnopf())
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Farbe.rose.opacity(0.35), lineWidth: 1))
        .shadow(color: Farbe.rose.opacity(0.18), radius: 20)
        .scaleEffect(da ? 1 : 0.94).opacity(da ? 1 : 0)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { zoom = true }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { da = true }
        }
    }
}

struct MiniKarte: View {
    let c: Charakter
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Bild als Überlagerung: füllt die Karte, ohne sie breiter zu machen (sonst rutscht der Name aus dem Bild)
            Color.clear.overlay { NetzBild(pfad: c.avatarUrl) }.clipped()
            LinearGradient(colors: [.clear, Farbe.grund.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                    Text("♡ Lv. \(c.beziehung.level)").font(.caption).foregroundStyle(Farbe.rose)
                }
                Spacer()
                Circle().fill(c.gerade.verfuegbar == "ja" ? Farbe.mint : .gray).frame(width: 8, height: 8)
            }
            .padding(10)
        }
        .frame(width: 130, height: 175)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
    }
}


/// Dein Status wie im Messenger – deine Charaktere sehen ihn und melden sich entsprechend (oder eben nicht).
struct StatusChip: View {
    @Environment(Verbindung.self) private var v
    struct S: Decodable { let status: String; let wirksam: String; let auto: Bool; let name: String; let farbe: String }
    @State private var s: S?
    private let wahl: [(id: String, name: String, farbe: Color, info: String)] = [
        ("verfuegbar", "Verfügbar", Color(red: 0.23, green: 0.82, blue: 0.49), "Sie melden sich, wie es zu euch passt"),
        ("abwesend", "Abwesend", Color(red: 0.96, green: 0.72, blue: 0.38), "Seltener, ohne Antwortdruck"),
        ("beschaeftigt", "Beschäftigt", Color(red: 1, green: 0.35, blue: 0.42), "Nur Enge melden sich, kurz"),
        ("unsichtbar", "Unsichtbar", Color(white: 0.55), "Du wirkst offline"),
    ]

    var body: some View {
        Menu {
            ForEach(wahl, id: \.id) { w in
                Button { Task { await setzen(w.id) } } label: {
                    Label { Text(w.name); Text(w.info) } icon: { Image(systemName: s?.status == w.id ? "checkmark.circle.fill" : "circle.fill") }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(farbe).frame(width: 9, height: 9).shadow(color: farbe, radius: 4)
                Text((s?.name ?? "Status") + ((s?.auto ?? false) ? " (auto)" : "")).font(.caption.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 10).padding(.vertical, 6).glas(14)
            .foregroundStyle(.white)
        }
        .task { await laden() }
    }

    private var farbe: Color { wahl.first { $0.id == s?.wirksam }?.farbe ?? .gray }

    @MainActor private func laden() async { s = try? await v.anfrage("/api/status/ich") }
    @MainActor private func setzen(_ id: String) async {
        struct B: Encodable { let status: String }
        if let n: S = try? await v.anfrage("/api/status/ich", methode: "PUT", body: B(status: id)) {
            UISelectionFeedbackGenerator().selectionChanged(); s = n
        }
    }
}
