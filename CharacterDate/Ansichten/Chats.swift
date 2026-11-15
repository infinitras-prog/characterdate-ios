import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct ChatListe: View {
    @Environment(Verbindung.self) private var v
    @Binding var auswahl: Charakter?
    @State private var lager = StoryLager()
    @State private var storyVon: Charakter?
    @State private var abo: UUID?

    var sortiert: [Charakter] {
        v.charaktere.filter { ($0.entwurf ?? 0) == 0 }.sorted { ($0.letzte?.zustellen ?? 0) > ($1.letzte?.zustellen ?? 0) }
    }

    var body: some View {
        List {
            ForEach(sortiert) { c in
                Button { auswahl = c } label: {
                    HStack(spacing: 12) {
                        StoryRing(hat: !(lager.storys[c.id] ?? []).isEmpty, neu: lager.neu(c.id)) {
                            Avatar(c: c, groesse: 52, online: true)
                        }
                        .onTapGesture { if !(lager.storys[c.id] ?? []).isEmpty { storyVon = c } else { auswahl = c } }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(c.name).font(.headline)
                                Spacer()
                                if let l = c.letzte { Text(uhrzeit(l.zustellen)).font(.caption).foregroundStyle(Farbe.text3) }
                            }
                            if c.tippt == true {
                                Text("schreibt …").font(.subheadline).foregroundStyle(Farbe.rose)
                            } else {
                                Text(c.letzte.map { ($0.rolle == "nutzer" ? "Du: " : "") + ($0.text.isEmpty ? "📎" : $0.text) } ?? "Sag Hallo 👋")
                                    .font(.subheadline).foregroundStyle(Farbe.text2).lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("Chats")
        .refreshable { await v.neuLaden() }
        .navigationDestination(item: $auswahl) { c in ChatAnsicht(charId: c.id) }
        .task { await lager.laden(v) }
        .onAppear { abo = v.abonnieren { e in if e.typ == "story" { Task { await lager.laden(v) } } } }
        .onDisappear { if let abo { v.abbestellen(abo) } }
        .fullScreenCover(item: $storyVon) { c in
            StoryBetrachter(c: c, storys: lager.storys[c.id] ?? []) { sid in
                if var l = lager.storys[c.id], let k = l.firstIndex(where: { $0.id == sid }) { l[k].gesehen = true; lager.storys[c.id] = l }
            }
        }
    }
}

struct ChatAnsicht: View {
    @Environment(Verbindung.self) private var v
    let charId: String
    @State private var nachrichten: [Nachricht] = []
    @State private var gelesenBis: Double = 0
    @State private var tippt = false
    @State private var tipptArt = "text"
    @State private var text = ""
    @State private var fehler: String?
    @State private var foto: PhotosPickerItem?
    @State private var gross: GrossesBild?
    @State private var abo: UUID?
    @State private var rekorder = Rekorder()
    @State private var anruf = false
    @State private var anrufMit: Charakter?       // fest beim Wählen gemerkt – unabhängig davon, ob die Liste kurz neu lädt
    @State private var mitVideo = false
    @State private var keineStimme = false
    @State private var vorlesen = false
    @State private var stimmeWaehlen = false
    @State private var stimmeFrage: URL?
    @State private var stimmeLaedt = false
    @State private var date: DateInfo?
    @State private var dateVideo = false
    @State private var liedBlatt = false
    @State private var dateWahl = false
    @State private var stimmeBearbeiten = false
    @State private var schlange: [String] = []
    @State private var liest: String?
    @State private var amEnde = true
    @State private var neuUnten = 0
    @FocusState private var fokus: Bool
    private var vorleseSchluessel: String { "vorlesen-\(charId)" }

    var c: Charakter? { v.charaktere.first { $0.id == charId } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { leser in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(nachrichten.enumerated()), id: \.element.id) { i, m in
                            if i == 0 || !Calendar.current.isDate(Date(timeIntervalSince1970: nachrichten[i - 1].zustellen),
                                                                   inSameDayAs: Date(timeIntervalSince1970: m.zustellen)) {
                                Text(tagText(m.zustellen)).font(.caption).foregroundStyle(Farbe.text3)
                                    .padding(.horizontal, 12).padding(.vertical, 4).background(.white.opacity(0.05), in: Capsule())
                                    .padding(.vertical, 8)
                            }
                            zeile(m).id(m.id)
                        }
                        if tippt, let c {
                            HStack(alignment: .bottom, spacing: 8) {
                                Avatar(c: c, groesse: 30)
                                if tipptArt == "sprache" {
                                    Label("nimmt eine Sprachnachricht auf …", systemImage: "mic.fill").font(.footnote)
                                        .padding(10).background(Color.white.opacity(0.08), in: Capsule())
                                } else { TippPunkte() }
                                Spacer()
                            }.id("tippt")
                        }
                        if let fehler { Text(fehler).font(.footnote).foregroundStyle(Farbe.rose).padding(8) }
                        Color.clear.frame(height: 1).id("ende")
                            .onAppear { amEnde = true; neuUnten = 0 }
                            .onDisappear { amEnde = false }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: nachrichten.count)
                    .animation(.easeOut(duration: 0.25), value: tippt)
                }
                .sensoryFeedback(.impact(weight: .light), trigger: nachrichten.count)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: nachrichten.count) { _, _ in
                    // nur mitscrollen, wenn du unten bist oder selbst geschrieben hast – sonst zählt der Pfeil mit
                    if amEnde || nachrichten.last?.vonMir == true { withAnimation { leser.scrollTo("ende", anchor: .bottom) } }
                    else { neuUnten += 1 }
                }
                .onChange(of: tippt) { _, an in if an && amEnde { withAnimation { leser.scrollTo("ende", anchor: .bottom) } } }
                .overlay(alignment: .bottom) {
                    if !amEnde {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { leser.scrollTo("ende", anchor: .bottom) }
                            neuUnten = 0
                        } label: {
                            Image(systemName: "chevron.down").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(Farbe.linie, lineWidth: 1))
                                .overlay(alignment: .topTrailing) {
                                    if neuUnten > 0 {
                                        Text("\(neuUnten)").font(.caption2.bold()).foregroundStyle(.white)
                                            .padding(.horizontal, 5).frame(minWidth: 19, minHeight: 19)
                                            .background(Farbe.rose, in: Capsule()).offset(x: 5, y: -5)
                                    }
                                }
                                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                        }
                        .accessibilityLabel("Ans Ende des Chats")
                        .padding(.bottom, 10)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: amEnde)
            }
            eingabe
        }
        .background(Hintergrund())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let c {
                    HStack(spacing: 8) {
                        Avatar(c: c, groesse: 34, online: true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.name).font(.headline)
                            Text(tippt ? (tipptArt == "sprache" ? "nimmt auf …" : "schreibt …") : "\(onlineText(c.gerade.verfuegbar)) · Lv. \(c.beziehung.level)")
                                .font(.caption2).foregroundStyle(tippt ? Farbe.rose : Farbe.text3)
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        if c?.hatStimme != true { keineStimme = true; return }
                        vorlesen.toggle(); UserDefaults.standard.set(vorlesen, forKey: vorleseSchluessel)
                        let an = vorlesen
                        Task { struct A: Decodable { let an: Bool }; let _: A? = try? await v.anfrage("/api/charaktere/\(charId)/vorlesen", methode: "PUT", body: ["an": an]) }
                        if !vorlesen { leiseStellen() }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: { Image(systemName: vorlesen ? "speaker.wave.2.fill" : "speaker.slash") }
                        .foregroundStyle(vorlesen ? Farbe.rose : Farbe.text2)
                        .accessibilityLabel(vorlesen ? "Vorlesen aus" : "Nachrichten vorlesen")
                        .disabled(c == nil || v.zustand != .verbunden)
                    Menu {
                        if let date {
                            Button(role: .destructive) { Task { await dateBeenden() } } label: { Label("Date beenden (\(date.ort))", systemImage: "heart.slash") }
                        } else {
                            Button { dateWahl = true } label: { Label("Date …", systemImage: "heart.circle") }
                        }
                        Button { dateVideo = true } label: { Label("Date-Video …", systemImage: "film.stack") }
                        Button { liedBlatt = true } label: { Label("Lied covern / Musikvideo …", systemImage: "music.mic") }
                        Button { Task { await storyJetzt() } } label: { Label("Story jetzt", systemImage: "sparkles") }
                        if c?.hatStimme == true {
                            Button { stimmeBearbeiten = true } label: { Label("Stimme bearbeiten", systemImage: "waveform.badge.magnifyingglass") }
                        }
                        Button { stimmeWaehlen = true } label: {
                            Label(c?.hatStimme == true ? "Neue Stimmprobe hochladen" : "Stimmprobe hochladen", systemImage: "waveform.badge.plus")
                        }
                    } label: { Image(systemName: stimmeLaedt ? "hourglass" : "ellipsis.circle") }
                        .disabled(c == nil || v.zustand != .verbunden || stimmeLaedt)
                    Button { if c?.hatStimme == true { mitVideo = true; anrufMit = c; anruf = true } else { keineStimme = true } } label: { Image(systemName: "video.fill") }
                        .accessibilityLabel("Videoanruf")
                        .disabled(c == nil || c?.avatarUrl == nil || v.zustand != .verbunden)
                    Button { if c?.hatStimme == true { mitVideo = false; anrufMit = c; anruf = true } else { keineStimme = true } } label: { Image(systemName: "phone.fill") }
                        .accessibilityLabel("Anrufen")
                        .disabled(c == nil || v.zustand != .verbunden)
                }
            }
        }
        .fullScreenCover(isPresented: $anruf) { if let a = anrufMit ?? c { AnrufAnsicht(c: a, video: mitVideo) } }
        .alert("Noch keine Stimme", isPresented: $keineStimme) {
            Button("Stimmprobe hochladen") { stimmeWaehlen = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(c?.name ?? "Sie") hat noch keine Stimme. Lade eine Stimmprobe hoch (MP3, WAV oder FLAC, bis 30 Sekunden) oder richte sie am PC im Editor ein – dann kannst du sie anrufen und dir ihre Nachrichten vorlesen lassen.")
        }
        .sheet(isPresented: $dateWahl) { if let c { DateWahl(c: c) { d in date = d } } }
        .sheet(isPresented: $stimmeBearbeiten) { if let c { StimmeBearbeiten(c: c) } }
        .safeAreaInset(edge: .top) {
            if let date {
                HStack {
                    Text("\(date.emoji) Date: ").font(.footnote) + Text(date.ort).font(.footnote.bold())
                    Spacer()
                    Button("Beenden") { Task { await dateBeenden() } }.font(.footnote.bold())
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(LinearGradient(colors: [Farbe.rose.opacity(0.25), Farbe.violett.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
            }
        }
        .fileImporter(isPresented: $stimmeWaehlen, allowedContentTypes: [.mp3, .wav, .audio, UTType(filenameExtension: "flac") ?? .audio]) { r in
            if case .success(let url) = r { stimmeFrage = url }
        }
        .confirmationDialog("Stimme übernehmen?", isPresented: Binding(get: { stimmeFrage != nil }, set: { if !$0 { stimmeFrage = nil } }), titleVisibility: .visible) {
            Button("Ja, die Stimme stammt von mir, einer erfundenen Figur oder einer Person, die zugestimmt hat") {
                if let u = stimmeFrage { Task { await stimmeHochladen(u) } }
            }
            Button("Abbrechen", role: .cancel) { stimmeFrage = nil }
        } message: {
            Text("Bis zu 30 Sekunden klare Sprache ohne Musik werden genutzt – je länger, desto genauer wird die Stimme kopiert.")
        }
        .task {
            vorlesen = UserDefaults.standard.bool(forKey: vorleseSchluessel) && c?.hatStimme == true
            struct DS: Decodable { let date: DateInfo? }
            if let d: DS = try? await v.anfrage("/api/charaktere/\(charId)/date") { date = d.date }
            await laden()
            // Stimme + Gehör am PC schon laden – Anrufe heben dann sofort ab
            if c?.hatStimme == true {
                struct Ok: Decodable { let ok: Bool }
                let _: Ok? = try? await v.anfrage("/api/stimme/vorwaermen", methode: "POST")
            }
            // Videoanruf-Szene (9:16) passend zum Chat schon vorbereiten – dann startet der Videoanruf ohne Wartezeit
            if c?.hatStimme == true, c?.avatarUrl != nil {
                struct Szene: Decodable { let url: String? }
                let _: Szene? = try? await v.anfrage("/api/charaktere/\(charId)/videoszene?format=hoch", methode: "POST")
            }
        }
        .onAppear {
            abo = v.abonnieren { e in
                guard e.charId == charId else { if e.typ == "verbunden" { Task { await laden() } }; return }
                switch e.typ {
                case "nachricht":
                    if let n = e.nachricht, !nachrichten.contains(where: { $0.id == n.id }) {
                        nachrichten.append(n)
                        if vorlesen && !n.vonMir && n.art == "text" && n.m("imAnruf") == nil
                            && !n.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { vorlesenLassen(n.id) }
                    }
                case "aktualisiert": if let n = e.nachricht, let i = nachrichten.firstIndex(where: { $0.id == n.id }) { nachrichten[i] = n }
                case "geloescht": if let mid = e.roh["nachricht_id"] as? String { nachrichten.removeAll { $0.id == mid } }
                case "gelesen": gelesenBis = e.roh["bis"] as? Double ?? gelesenBis
                case "tippt": tippt = e.roh["an"] as? Bool ?? false; tipptArt = e.roh["art"] as? String ?? "text"
                case "fehler": fehler = e.roh["text"] as? String; tippt = false
                default: break
                }
            }
        }
        .onDisappear { if let abo { v.abbestellen(abo) }; leiseStellen() }
        .onChange(of: foto) { _, neu in if let neu { Task { await fotoSenden(neu) } } }
        .fullScreenCover(item: $gross) { b in BildVollbild(bild: b, geaendert: { Task { await laden() } }) }
        .sheet(isPresented: $dateVideo) { if let c { DateVideoBlatt(c: c, ort: date?.ort) } }
        .sheet(isPresented: $liedBlatt) { if let c { LiedBlatt(c: c) } }
    }

    // MARK: Zeilen

    @ViewBuilder
    private func zeile(_ m: Nachricht) -> some View {
        if m.art == "date" {
            Text(m.text).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 5)
                .background(Farbe.rose.opacity(0.18), in: Capsule()).padding(.vertical, 6)
        } else if m.art == "anruf" {
            Label(m.m("verpasst")?.wahr == true ? "Verpasster Anruf · \(uhrzeit(m.zustellen))" : "Telefonat · \(m.m("dauerText")?.text ?? "") · \(uhrzeit(m.zustellen))",
                  systemImage: m.m("verpasst")?.wahr == true ? "phone.down" : "phone")
                .font(.footnote).padding(.horizontal, 14).padding(.vertical, 6)
                .background(Farbe.mint.opacity(0.08), in: Capsule()).padding(.vertical, 6)
        } else if m.m("imAnruf") != nil {
            Text("📞 \(m.vonMir ? "Du" : c?.name ?? ""): \(m.text)").font(.footnote.italic()).foregroundStyle(Farbe.text2)
                .frame(maxWidth: .infinity, alignment: m.vonMir ? .trailing : .leading)
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                if m.vonMir { Spacer(minLength: 50) } else if let c { Avatar(c: c, groesse: 30) }
                inhalt(m)
                if !m.vonMir { Spacer(minLength: 50) }
            }
            .transition(.asymmetric(insertion: .scale(scale: 0.86, anchor: m.vonMir ? .bottomTrailing : .bottomLeading).combined(with: .opacity),
                                    removal: .opacity))
        }
    }

    @ViewBuilder
    private func inhalt(_ m: Nachricht) -> some View {
        let ich = m.vonMir
        switch m.art {
        case "bild":
            if !ich && m.m("status")?.text == "entsteht" {
                ErstellungsKarte(nid: m.id, titel: m.m("kritik") != nil ? "Neues Foto" : m.m("art")?.text == "aenderung" ? "Foto wird geändert"
                                 : m.m("art")?.text == "wirfoto" ? "Euer Foto" : "Foto",
                                 symbol: m.m("art")?.text == "wirfoto" ? "heart.fill" : m.m("art")?.text == "aenderung" ? "wand.and.stars" : "camera.fill")
            } else if let pfad = m.m("bild")?.text {
                VStack(alignment: .leading, spacing: 0) {
                    NetzBild(pfad: pfad).frame(width: 230, height: 300).clipped()
                    HStack {
                        if !m.text.isEmpty { Text(m.text).font(.footnote) }
                        Spacer()
                        Text(uhrzeit(m.zustellen)).font(.caption2).foregroundStyle(Farbe.text3)
                    }.padding(8)
                }
                .frame(width: 230)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture { gross = GrossesBild(pfad: pfad, bildId: m.m("bildId")?.text) }
            } else {
                Text("📷 Das Foto ist nicht geworden.").font(.footnote).padding(10).glas(16)
            }
        case "musik":
            if !ich && m.m("status")?.text == "entsteht" {
                ErstellungsKarte(nid: m.id, titel: "Ihr Cover", symbol: "music.note")
            } else if !ich && m.m("status")?.text == "fehler" {
                Text("🎵 Das Cover ist nicht geworden.").font(.footnote).padding(10).glas(16)
            } else {
                MusikKarte(m: m)
            }
        case "video":
            if m.m("status")?.text == "entsteht" {
                ErstellungsKarte(nid: m.id, titel: m.m("art")?.text == "datevideo" ? "Euer Date-Video"
                                 : m.m("art")?.text == "musikvideo" ? "Musikvideo" : "Video",
                                 symbol: m.m("art")?.text == "datevideo" ? "heart.fill" : "film.fill", breite: 240)
            } else if let pfad = m.m("video")?.text {
                ChatVideo(pfad: pfad).frame(width: 230, height: 330).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text("🎬 Das Video ist nicht geworden.").font(.footnote).padding(10).glas(16)
            }
        case "sprache":
            VStack(alignment: .leading, spacing: 6) {
                if let a = m.m("audio")?.text { SprachBlase(pfad: a, dauer: m.m("dauer")?.zahl, hell: ich) }
                Text(m.m("status")?.text == "versteht" ? "wird verstanden …" : m.text).font(.footnote).opacity(0.8)
            }
            .padding(10).background(blasenGrund(ich), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        default:
            VStack(alignment: .trailing, spacing: 2) {
                Text(m.text).font(.body)
                HStack(spacing: 3) {
                    Text(uhrzeit(m.zustellen))
                    if ich { Image(systemName: gelesenBis >= m.erstellt ? "checkmark.circle.fill" : "checkmark").foregroundStyle(gelesenBis >= m.erstellt ? Farbe.mint : .white.opacity(0.6)) }
                }.font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(blasenGrund(ich), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(liest == m.id ? Farbe.rose : (ich ? Color.clear : Farbe.linie), lineWidth: liest == m.id ? 1.5 : 1))
            .contextMenu {
                if !ich && c?.hatStimme == true {
                    Button { if liest == m.id { leiseStellen() } else { leiseStellen(); vorlesenLassen(m.id) } } label: {
                        Label(liest == m.id ? "Vorlesen stoppen" : "Vorlesen", systemImage: liest == m.id ? "speaker.slash" : "speaker.wave.2")
                    }
                }
                Button { UIPasteboard.general.string = m.text } label: { Label("Kopieren", systemImage: "doc.on.doc") }
            }
        }
    }

    private func blasenGrund(_ ich: Bool) -> AnyShapeStyle {
        ich ? AnyShapeStyle(LinearGradient(colors: [Farbe.violett.opacity(0.85), Farbe.rose.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(Color(red: 0.17, green: 0.15, blue: 0.25).opacity(0.9))
    }

    // MARK: Eingabe

    private var eingabe: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $foto, matching: .images) {
                Image(systemName: "plus").font(.title3).frame(width: 40, height: 40)
            }
            if rekorder.laeuft {
                HStack {
                    Circle().fill(.red).frame(width: 9, height: 9)
                    Text("Sprachnachricht · \(rekorder.sekunden / 60):\(String(format: "%02d", rekorder.sekunden % 60))").monospacedDigit()
                    Spacer()
                    Button { _ = rekorder.stopp(verwerfen: true) } label: { Image(systemName: "xmark") }
                }
                .padding(.horizontal, 14).frame(height: 44).glas(22)
            } else {
                TextField("Nachricht an \(c?.name ?? "") …", text: $text, axis: .vertical)
                    .lineLimit(1...5).focused($fokus)
                    .padding(.horizontal, 14).padding(.vertical, 11).glas(22)
            }
            Button {
                if rekorder.laeuft { Task { await spracheSenden() } }
                else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task { do { try await rekorder.start() } catch { fehler = error.localizedDescription } }
                } else { Task { await senden() } }
            } label: {
                Image(systemName: rekorder.laeuft || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "paperplane.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Farbe.verlauf, in: Circle())
                    .shadow(color: Farbe.rose.opacity(0.45), radius: 10)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.6))
    }

    // MARK: Vorlesen (ihre Stimme)

    @MainActor
    private func vorlesenLassen(_ mid: String) {
        schlange.append(mid)
        if liest == nil { Task { await naechsteVorlesen() } }
    }

    @MainActor
    private func leiseStellen() {
        schlange.removeAll(); liest = nil
        if Abspieler.shared.beiEnde != nil || Abspieler.shared.aktuell?.contains("/vorlesen/") == true { Abspieler.shared.stopp() }
    }

    @MainActor
    private func naechsteVorlesen() async {
        guard liest == nil, !schlange.isEmpty else { return }
        let mid = schlange.removeFirst()
        liest = mid
        struct Antwort: Decodable { let url: String }
        do {
            let r: Antwort = try await v.anfrage("/api/nachrichten/\(mid)/vorlesen", methode: "POST", zeit: 180)
            guard liest == mid else { return }                       // inzwischen gestoppt
            await Abspieler.shared.umschalten(r.url, v: v)
            if Abspieler.shared.aktuell == nil { liest = nil; await naechsteVorlesen(); return }
            Abspieler.shared.beiEnde = { Task { @MainActor in liest = nil; await naechsteVorlesen() } }
        } catch {
            liest = nil; schlange.removeAll(); fehler = error.localizedDescription
        }
    }

    @MainActor
    private func dateBeenden() async {
        struct A: Decodable {}
        let _: A? = try? await v.anfrage("/api/charaktere/\(charId)/date/ende", methode: "POST")
        date = nil
    }

    @MainActor
    private func storyJetzt() async {
        struct A: Decodable { let id: String }
        do { let _: A = try await v.anfrage("/api/charaktere/\(charId)/story", methode: "POST", zeit: 300) }
        catch { fehler = error.localizedDescription }
    }

    @MainActor
    private func stimmeHochladen(_ url: URL) async {
        stimmeFrage = nil; stimmeLaedt = true; fehler = nil
        defer { stimmeLaedt = false }
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: url) else { fehler = "Die Datei konnte nicht gelesen werden."; return }
        let endung = url.pathExtension.lowercased()
        do {
            let _: Charakter = try await v.hochladen("/api/charaktere/\(charId)/stimme/klonen", datei: d, name: "probe.\(endung.isEmpty ? "mp3" : endung)",
                                                     typ: "audio/\(endung == "mp3" ? "mpeg" : endung)", felder: ["einverstanden": "true", "sprache": "de"])
            await v.neuLaden()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch { fehler = error.localizedDescription }
    }

    // MARK: Aktionen

    @MainActor
    private func laden() async {
        do {
            let r: ChatAntwort = try await v.anfrage("/api/charaktere/\(charId)/chat")
            nachrichten = r.nachrichten
            gelesenBis = r.gelesenBis ?? 0
            tippt = c?.tippt ?? false
            Ablage.schreiben(r, "chat_" + charId)
        } catch {
            if let alt = Ablage.lesen(ChatAntwort.self, "chat_" + charId) {
                nachrichten = alt.nachrichten; gelesenBis = alt.gelesenBis ?? 0
                fehler = "Offline – zuletzt geladener Stand. Neue Nachrichten gehen, sobald der PC erreichbar ist."
            } else { fehler = error.localizedDescription }
        }
    }

    @MainActor
    private func senden() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        text = ""; fehler = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do { let _: Nachricht = try await v.anfrage("/api/charaktere/\(charId)/nachricht", methode: "POST", body: ["text": t]) }
        catch { fehler = error.localizedDescription; text = t }
    }

    @MainActor
    private func fotoSenden(_ item: PhotosPickerItem) async {
        defer { foto = nil }
        guard let d = try? await item.loadTransferable(type: Data.self), let bild = UIImage(data: d),
              let jpg = bild.jpegData(compressionQuality: 0.88) else { fehler = "Das Foto konnte nicht geladen werden."; return }
        let t = text; text = ""
        do { let _: Nachricht = try await v.hochladen("/api/charaktere/\(charId)/foto", datei: jpg, name: "foto.jpg", typ: "image/jpeg", felder: ["text": t]) }
        catch { fehler = error.localizedDescription; text = t }
    }

    @MainActor
    private func spracheSenden() async {
        guard let d = rekorder.stopp() else { return }
        do {
            struct Ok: Decodable { let ok: Bool }
            let _: Ok = try await v.hochladen("/api/charaktere/\(charId)/sprachnachricht", datei: d, name: "nachricht.m4a", typ: "audio/mp4")
        } catch { fehler = error.localizedDescription }
    }
}

struct GrossesBild: Identifiable { let pfad: String; var bildId: String? = nil; var id: String { pfad } }

struct TippPunkte: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(Farbe.rose).frame(width: 7, height: 7)
                    .offset(y: sin(phase + Double(i) * 0.9) * 3)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(red: 0.17, green: 0.15, blue: 0.25), in: Capsule())
        .onAppear { DispatchQueue.main.async { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi * 2 } } }
    }
}
