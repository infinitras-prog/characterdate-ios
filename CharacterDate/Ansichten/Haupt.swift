import SwiftUI

struct HauptAnsicht: View {
    @Environment(Verbindung.self) private var v
    @State private var tab = 0
    @State private var chatMit: Charakter?

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
                NavigationStack { ErstellenAnsicht(fertig: { c in chatMit = c; tab = 1 }) }
                    .tabItem { Label("Char erstellen", systemImage: "plus.circle") }.tag(2)
                NavigationStack { GalerieAnsicht() }
                    .tabItem { Label("Galerie", systemImage: "photo") }.tag(3)
                NavigationStack { EinstellungenAnsicht() }
                    .tabItem { Label("Einstellungen", systemImage: "gearshape") }.tag(4)
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
                    Text("Entdecken").font(.title2.weight(.semibold))
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
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NetzBild(pfad: c.avatarUrl)
            LinearGradient(colors: [.clear, .clear, Farbe.grund.opacity(0.95)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(c.name).font(.system(size: 32, weight: .semibold, design: .rounded)); Image(systemName: "heart").foregroundStyle(Farbe.rose) }
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
    }
}

struct MiniKarte: View {
    let c: Charakter
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NetzBild(pfad: c.avatarUrl)
            LinearGradient(colors: [.clear, Farbe.grund.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.headline)
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
