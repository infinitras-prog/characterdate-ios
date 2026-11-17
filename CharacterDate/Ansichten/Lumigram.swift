import SwiftUI

// MARK: - Daten

struct LumiKontoKurz: Decodable, Hashable { let id: String; let name: String; var anzeige: String?; let avatar: String? }

struct LumiPost: Decodable, Identifiable, Hashable {
    let id: String
    let art: String
    let text: String
    let ort: String
    let zeit: Double
    let medien: [String]
    var likes: Int
    var kommentare: Int
    var geliked: Bool
    let konto: LumiKontoKurz
    var poster: String? = nil
    var hashtags: [String]? = nil
    var ichFolge: Bool? = nil
}

struct LumiKonto: Decodable, Identifiable {
    let id: String
    let art: String
    let name: String
    let anzeige: String
    let bio: String
    let avatar: String?
    var follower: Int
    let folgt: Int
    let postsAnzahl: Int
    var ichFolge: Bool
    let folgtMir: Bool
    let istIch: Bool
    let posts: [LumiPost]
    let charId: String?
    var storys: [LumiStory]? = nil
    var highlights: [LumiStory]? = nil
}

struct LumiKommentar: Decodable, Identifiable { let id: String; let text: String; let zeit: Double; let antwortAuf: String?; let konto: LumiKontoKurz }

private struct KontoHuelle: Decodable { let konto: LumiKonto? }
private struct FeedHuelle: Decodable { let posts: [LumiPost] }
private struct KomHuelle: Decodable { let kommentare: [LumiKommentar] }

enum Lumi {
    static func zahl(_ n: Int) -> String {
        n >= 10_000 ? String(format: "%.1f Tsd.", Double(n) / 1000).replacingOccurrences(of: ".", with: ",", options: .backwards, range: nil)
            : n.formatted(.number.locale(Locale(identifier: "de_DE")))
    }
    static func vor(_ t: Double) -> String {
        let s = Date().timeIntervalSince1970 - t
        if s < 60 { return "gerade eben" }
        if s < 3600 { return "vor \(Int(s / 60)) Min." }
        if s < 86400 { return "vor \(Int(s / 3600)) Std." }
        if s < 86400 * 7 { return "vor \(Int(s / 86400)) T." }
        return Date(timeIntervalSince1970: t).formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "de_DE")))
    }
    static var logo: some View {
        Text("Lumigram").font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(LinearGradient(colors: [Color(red: 0.96, green: 0.72, blue: 0.38), Farbe.rose, Farbe.violett],
                                            startPoint: .leading, endPoint: .trailing))
    }
}

// MARK: - Hauptansicht (Aufbau wie die Instagram-App am iPhone)

enum IG {
    static let blau = Color(red: 0, green: 0.584, blue: 0.965)
    static let grau = Color(white: 0.66)
    static let feld = Color(white: 0.15)
    static let linie = Color(white: 0.15)
    static let ring = AngularGradient(colors: [Color(red: 1, green: 0.84, blue: 0), Color(red: 1, green: 0.48, blue: 0),
                                               Color(red: 1, green: 0, blue: 0.41), Color(red: 0.83, green: 0, blue: 0.77),
                                               Color(red: 0.46, green: 0.22, blue: 0.98), Color(red: 1, green: 0.84, blue: 0)],
                                      center: .center)
    static func logo(_ groesse: CGFloat = 30) -> some View {
        Text("Lumigram").font(.custom("SnellRoundhand-Bold", size: groesse)).foregroundStyle(.white)
    }
}

struct LumigramAnsicht: View {
    @Environment(Verbindung.self) private var v
    var chatOeffnen: (Charakter) -> Void = { _ in }
    var zurueck: () -> Void = {}
    var zuChats: () -> Void = {}
    @State private var ich: LumiKonto?
    @State private var geladen = false
    @State private var tab = 0
    @State private var pfad = NavigationPath()
    @State private var erstellen = false
    @State private var neu = 0

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $pfad) {
                Group {
                    if !geladen {
                        ProgressView().tint(.white)
                    } else if ich == nil {
                        LumiAnmelden { await laden() }
                    } else {
                        switch tab {
                        case 0: LumiFeed(pfad: $pfad)
                        case 1: LumiSuche(pfad: $pfad)
                        case 3: LumiReels(pfad: $pfad)
                        case 4: LumiMitteilungen(pfad: $pfad)
                        default: if let ich { LumiKontoAnsicht(id: ich.id, pfad: $pfad, chatOeffnen: chatOeffnen) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 6) {
                            Button { zurueck() } label: { Image(systemName: "chevron.left").font(.body.weight(.semibold)) }
                                .accessibilityLabel("Zurück zu CharacterDate")
                            if tab == 2, let ich { Text(ich.name).font(.title3.bold()) } else { IG.logo(28) }
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { pfad = NavigationPath(); tab = 4; neu = 0 } label: {
                            Image(systemName: tab == 4 ? "heart.fill" : "heart").font(.title3)
                                .overlay(alignment: .topTrailing) {
                                    if neu > 0 { Circle().fill(Color(red: 1, green: 0.19, blue: 0.25)).frame(width: 9, height: 9).offset(x: 3, y: -2) }
                                }
                        }.accessibilityLabel("Mitteilungen")
                        Button { zuChats() } label: { Image(systemName: "paperplane").font(.title3) }.accessibilityLabel("Nachrichten")
                    }
                }
                .toolbarBackground(Color.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { kid in LumiKontoAnsicht(id: kid, pfad: $pfad, chatOeffnen: chatOeffnen) }
                .navigationDestination(for: LumiPost.self) { p in LumiPostAnsicht(post: p, pfad: $pfad) }
            }
            if ich != nil {
                // eigene Leiste unten wie in der Instagram-App
                HStack {
                    leistenKnopf(0, "house", "house.fill")
                    leistenKnopf(1, "magnifyingglass", "magnifyingglass")
                    Button { erstellen = true } label: { Image(systemName: "plus.app").font(.title2) }.frame(maxWidth: .infinity)
                        .accessibilityLabel("Beitrag erstellen")
                    leistenKnopf(3, "play.rectangle", "play.rectangle.fill")
                    Button { pfad = NavigationPath(); tab = 2 } label: {
                        LumiAvatar(k: LumiKontoKurz(id: ich!.id, name: ich!.name, anzeige: nil, avatar: ich!.avatar), groesse: 26, ring: false)
                            .overlay(Circle().stroke(.white, lineWidth: tab == 2 ? 1.5 : 0).padding(-2))
                    }
                    .frame(maxWidth: .infinity)
                }
                .foregroundStyle(.white)
                .padding(.top, 10).padding(.bottom, 4)
                .background(Color.black.overlay(alignment: .top) { IG.linie.frame(height: 0.5) })
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .tabBar)
        .task { await laden() }
        .sheet(isPresented: $erstellen) { LumiErstellen { pfad = NavigationPath(); tab = 2 } }
    }

    private func leistenKnopf(_ i: Int, _ aus: String, _ an: String) -> some View {
        Button {
            if tab == i { pfad = NavigationPath() }
            tab = i
        } label: {
            Image(systemName: tab == i ? an : aus).font(.title2.weight(tab == i ? .bold : .regular))
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor private func laden() async {
        if let h: KontoHuelle = try? await v.anfrage("/api/lumi/ich") { ich = h.konto; LumiStand.ichId = h.konto?.id }
        struct U: Decodable { let ungelesen: Int }
        if let u: U = try? await v.anfrage("/api/lumi/mitteilungen") { neu = u.ungelesen }
        geladen = true
    }
}

private struct LumiAnmelden: View {
    @Environment(Verbindung.self) private var v
    let fertig: () async -> Void
    @State private var name = ""
    @State private var bio = ""
    @State private var fehler: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Lumi.logo.scaleEffect(1.5)
            Text("Leg deinen Nutzernamen fest. Deine Charaktere haben eigene Konten – ihren @Namen musst du sie im Chat fragen.")
                .font(.footnote).foregroundStyle(Farbe.text2).multilineTextAlignment(.center)
            HStack {
                Image(systemName: "at").foregroundStyle(Farbe.text2)
                TextField("dein.name", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onChange(of: name) { _, n in name = String(n.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }.prefix(30)) }
            }
            .padding(12).glas(14)
            TextField("Bio (optional)", text: $bio, axis: .vertical).lineLimit(1...3).padding(12).glas(14)
            if let fehler { Text(fehler).font(.footnote).foregroundStyle(.orange) }
            Button("Los geht's") {
                Task {
                    struct I: Encodable { let name: String; let bio: String }
                    do { _ = try await v.roh("/api/lumi/ich", methode: "PUT", body: I(name: name, bio: bio)); await fertig() }
                    catch { fehler = error.localizedDescription }
                }
            }
            .buttonStyle(HauptKnopf()).disabled(name.count < 3)
            Spacer()
        }
        .padding(24)
    }
}

// MARK: - Feed

private struct LumiFeed: View {
    @Environment(Verbindung.self) private var v
    @Binding var pfad: NavigationPath
    @State private var posts: [LumiPost]?
    @State private var gefolgt: [LumiGefolgt] = []
    @State private var lager = StoryLager()
    @State private var storyVon: Charakter?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                storyLeiste
                if let posts {
                    if posts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.circle").font(.system(size: 60, weight: .thin))
                            Text("Willkommen bei Lumigram").font(.title3.bold())
                            Text("Frag deine Charaktere im Chat nach ihrem Lumigram-Namen und such sie dann über die Lupe.")
                                .font(.subheadline).foregroundStyle(IG.grau).multilineTextAlignment(.center)
                        }
                        .padding(40)
                    } else {
                        ForEach(posts) { p in LumiPostKarte(post: p, pfad: $pfad).padding(.bottom, 14) }
                    }
                } else {
                    ProgressView().tint(.white).padding(60)
                }
            }
        }
        .background(Color.black)
        .refreshable { await laden() }
        .task { await laden() }
        .fullScreenCover(item: $storyVon) { c in
            StoryBetrachter(c: c, storys: lager.storys[c.id] ?? []) { sid in
                if var l = lager.storys[c.id], let k = l.firstIndex(where: { $0.id == sid }) { l[k].gesehen = true; lager.storys[c.id] = l }
            }
        }
    }

    @ViewBuilder private var storyLeiste: some View {
        let mit = gefolgt.filter { g in g.charId.map { !(lager.storys[$0] ?? []).isEmpty } ?? false }
        if !mit.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(mit) { g in
                        Button {
                            if let cid = g.charId, let c = v.charaktere.first(where: { $0.id == cid }) { storyVon = c }
                        } label: {
                            VStack(spacing: 5) {
                                LumiAvatar(k: LumiKontoKurz(id: g.id, name: g.name, anzeige: g.anzeige, avatar: g.avatar), groesse: 64,
                                           ring: true, gesehen: !(lager.storys[g.charId ?? ""] ?? []).contains { !$0.gesehen })
                                Text(g.name).font(.caption2).lineLimit(1).frame(width: 74)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            IG.linie.frame(height: 0.5).padding(.bottom, 8)
        }
    }

    @MainActor private func laden() async {
        if let f: FeedHuelle = try? await v.anfrage("/api/lumi/feed") { posts = f.posts } else if posts == nil { posts = [] }
        if let g: GefolgtHuelle = try? await v.anfrage("/api/lumi/gefolgt") { gefolgt = g.konten }
        await lager.laden(v)
    }
}

struct LumiGefolgt: Decodable, Identifiable { let id: String; let name: String; let anzeige: String?; let charId: String?; let avatar: String?; let folgtMir: Bool? }
private struct GefolgtHuelle: Decodable { let konten: [LumiGefolgt] }

struct LumiAvatar: View {
    let k: LumiKontoKurz
    var groesse: CGFloat = 34
    var ring: Bool = true
    var gesehen: Bool = false
    var body: some View {
        let bild = ZStack {
            if let a = k.avatar { Color.clear.overlay { NetzBild(pfad: a) } } else {
                Circle().fill(Color(white: 0.25))
                Text(String(k.name.prefix(1)).uppercased()).font(.system(size: groesse * 0.42, weight: .semibold))
            }
        }
        .frame(width: groesse, height: groesse).clipShape(Circle())
        if ring {
            bild.padding(groesse > 40 ? 3 : 2)
                .background(Circle().fill(Color.black))
                .padding(groesse > 40 ? 2.5 : 2)
                .background(Circle().fill(gesehen ? AnyShapeStyle(Color(white: 0.3)) : AnyShapeStyle(IG.ring)))
        } else {
            bild
        }
    }
}

struct LumiPostKarte: View {
    @Environment(Verbindung.self) private var v
    @State var post: LumiPost
    @Binding var pfad: NavigationPath
    @State private var herz = false
    @State private var teilen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { pfad.append(post.konto.id) } label: {
                HStack(spacing: 10) {
                    LumiAvatar(k: post.konto, groesse: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.konto.name).font(.footnote.weight(.semibold))
                        if !post.ort.isEmpty { Text(post.ort).font(.caption2) }
                    }
                    Spacer()
                    Image(systemName: "ellipsis").font(.footnote)
                }
            }
            .buttonStyle(.plain).padding(.horizontal, 12)
            ZStack {
                if let m = post.medien.first {
                    Color.clear.aspectRatio(4 / 5, contentMode: .fit).frame(maxWidth: .infinity)
                        .overlay { LumiMedium(pfad: m, poster: post.poster) }.clipped()
                } else {
                    Text(post.text).font(.title3).padding(30).frame(maxWidth: .infinity, minHeight: 240)
                        .background(Farbe.verlauf.opacity(0.4))
                }
                Image(systemName: "heart.fill").font(.system(size: 90)).foregroundStyle(.white)
                    .shadow(radius: 12).scaleEffect(herz ? 1 : 0.2).opacity(herz ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { herz = true }
                Task { try? await Task.sleep(for: .milliseconds(700)); withAnimation { herz = false } }
                if !post.geliked { Task { await liken(true) } }
            }
            HStack(spacing: 16) {
                Button { Task { await liken(!post.geliked) } } label: {
                    Image(systemName: post.geliked ? "heart.fill" : "heart").font(.title2)
                        .foregroundStyle(post.geliked ? Color(red: 1, green: 0.19, blue: 0.25) : .white)
                        .symbolEffect(.bounce, value: post.geliked)
                }
                Button { pfad.append(post) } label: { Image(systemName: "bubble.right").font(.title2) }
                Button { teilen = true } label: { Image(systemName: "paperplane").font(.title2) }
                Spacer()
                Image(systemName: "bookmark").font(.title2)
            }
            .buttonStyle(.plain).padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Lumi.zahl(post.likes)) „Gefällt mir“-Angaben").font(.footnote.bold())
                if !post.text.isEmpty { (Text(post.konto.name).bold() + Text(" " + post.text)).font(.footnote) }
                if let h = post.hashtags, !h.isEmpty { Text(h.map { "#" + $0 }.joined(separator: " ")).font(.footnote).foregroundStyle(Color(red: 0.88, green: 0.95, blue: 1)) }
                if post.kommentare > 0 {
                    Button("Alle \(post.kommentare) Kommentare ansehen") { pfad.append(post) }
                        .font(.footnote).foregroundStyle(IG.grau)
                }
                Text(Lumi.vor(post.zeit)).font(.caption2).foregroundStyle(IG.grau)
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 10)
        .sheet(isPresented: $teilen) { LumiTeilen(post: post).presentationDetents([.medium]) }
    }

    @MainActor private func liken(_ an: Bool) async {
        let alt = post
        post.geliked = an
        post.likes += an == alt.geliked ? 0 : (an ? 1 : -1)
        struct A: Encodable { let an: Bool }
        if var n: LumiPost = try? await v.anfrage("/api/lumi/posts/\(post.id)/like", methode: "POST", body: A(an: an)) {
            if n.poster == nil { n.poster = alt.poster }
            post = n
        }
    }
}

// MARK: - Suche

private struct LumiSuche: View {
    @Environment(Verbindung.self) private var v
    @Binding var pfad: NavigationPath
    @State private var q = ""
    @State private var nichts = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(IG.grau)
                TextField("Suchen", text: $q)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .onSubmit { Task { await suchen() } }
                if !q.isEmpty { Button { q = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(IG.grau) } }
            }
            .padding(.horizontal, 12).frame(height: 38).background(IG.feld, in: RoundedRectangle(cornerRadius: 10))
            if nichts {
                VStack(spacing: 6) {
                    Text("Keine Ergebnisse").font(.headline)
                    Text("Kein Konto heißt genau @\(q.replacingOccurrences(of: "@", with: "")).").font(.footnote).foregroundStyle(IG.grau)
                }.padding(.top, 30)
            } else if q.isEmpty {
                ScrollView { LumiEntdecken(pfad: $pfad) }
            } else {
                Text("Gib den genauen Nutzernamen ein, den sie dir im Chat verraten hat.")
                    .font(.footnote).foregroundStyle(IG.grau).multilineTextAlignment(.center).padding(.top, 30)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.top, 6)
        .background(Color.black)
    }

    @MainActor private func suchen() async {
        nichts = false
        let n = q.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let h: KontoHuelle = try? await v.anfrage("/api/lumi/suche?name=\(n)"), let k = h.konto {
            pfad.append(k.id)
        } else { nichts = true }
    }
}

// MARK: - Profil

struct LumiKontoAnsicht: View {
    @Environment(Verbindung.self) private var v
    let id: String
    @Binding var pfad: NavigationPath
    var chatOeffnen: (Charakter) -> Void = { _ in }
    @State private var k: LumiKonto?
    @State private var zeige: [LumiStory]?

    var body: some View {
        ScrollView {
            if let k {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 24) {
                        LumiAvatar(k: LumiKontoKurz(id: k.id, name: k.name, anzeige: k.anzeige, avatar: k.avatar), groesse: 84, ring: !(k.storys ?? []).isEmpty)
                            .onTapGesture { if let s = k.storys, !s.isEmpty { zeige = s } }
                        HStack(spacing: 0) {
                            zahl(k.postsAnzahl, "Beiträge").frame(maxWidth: .infinity)
                            zahl(k.follower, "Follower").frame(maxWidth: .infinity)
                            zahl(k.folgt, "Gefolgt").frame(maxWidth: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k.anzeige.isEmpty ? k.name : k.anzeige).font(.footnote.weight(.semibold))
                        if !k.bio.isEmpty { Text(k.bio).font(.footnote) }
                    }
                    if !k.istIch {
                        HStack(spacing: 8) {
                            Button { Task { await folgen(!k.ichFolge) } } label: {
                                Text(k.ichFolge ? "Gefolgt" : k.folgtMir ? "Zurückfolgen" : "Folgen")
                                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 34)
                                    .background(k.ichFolge ? IG.feld : IG.blau, in: RoundedRectangle(cornerRadius: 8))
                            }
                            if let cid = k.charId, let c = v.charaktere.first(where: { $0.id == cid }) {
                                Button { chatOeffnen(c) } label: {
                                    Text("Nachricht").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 34)
                                        .background(IG.feld, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        if k.folgtMir { Text("Folgt dir").font(.caption2).foregroundStyle(IG.grau) }
                    }
                    }
                    .padding(.horizontal, 16)
                    if let h = k.highlights, !h.isEmpty { LumiHighlights(highlights: h) { zeige = $0 } }
                    HStack { Spacer(); Image(systemName: "squareshape.split.3x3").font(.title3); Spacer() }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Rectangle().fill(.white).frame(height: 1).frame(maxWidth: 120) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 3), spacing: 1.5) {
                        ForEach(k.posts) { p in
                            Button { pfad.append(p) } label: { LumiKachel(p: p) }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 12)
            } else {
                ProgressView().tint(.white).padding(60)
            }
        }
        .background(Color.black)
        .refreshable { await laden() }
        .task { await laden() }
        .fullScreenCover(item: Binding(get: { zeige.map { StoryListe(storys: $0) } }, set: { if $0 == nil { zeige = nil } })) { l in
            LumiStoryBlatt(storys: l.storys)
        }
    }

    private struct StoryListe: Identifiable { let storys: [LumiStory]; var id: String { storys.map(\.url).joined() } }

    private func zahl(_ n: Int, _ t: String) -> some View {
        VStack(spacing: 1) { Text(Lumi.zahl(n)).font(.headline); Text(t).font(.caption2).foregroundStyle(Farbe.text2) }
    }

    @MainActor private func laden() async { k = try? await v.anfrage("/api/lumi/konto/\(id)") }

    @MainActor private func folgen(_ an: Bool) async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        struct A: Encodable { let an: Bool }
        if let n: LumiKonto = try? await v.anfrage("/api/lumi/konto/\(id)/folgen", methode: "POST", body: A(an: an)) {
            withAnimation(.spring) { k = n }
        }
    }
}

// MARK: - Post mit Kommentaren

private struct LumiPostAnsicht: View {
    @Environment(Verbindung.self) private var v
    let post: LumiPost
    @Binding var pfad: NavigationPath
    @State private var kom: [LumiKommentar] = []
    @State private var text = ""
    @State private var loeschen = false
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LumiPostKarte(post: post, pfad: $pfad)
                    ForEach(kom) { c in
                        HStack(alignment: .top, spacing: 10) {
                            LumiAvatar(k: c.konto, groesse: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                (Text(c.konto.name).bold() + Text(" " + c.text)).font(.footnote)
                                Text(Lumi.vor(c.zeit)).font(.caption2).foregroundStyle(IG.grau)
                            }
                            Spacer()
                        }
                        .padding(.leading, c.antwortAuf == nil ? 12 : 42).padding(.trailing, 12)
                    }
                }
            }
            HStack {
                TextField("Kommentieren …", text: $text).submitLabel(.send).onSubmit { Task { await senden() } }
                Button("Posten") { Task { await senden() } }.font(.subheadline.bold()).foregroundStyle(Farbe.rose)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12).background(.ultraThinMaterial)
        }
        .background(Color.black)
        .navigationTitle("Beitrag").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if post.konto.id == LumiStand.ichId {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { loeschen = true } label: { Image(systemName: "trash") }
                }
            }
        }
        .confirmationDialog("Beitrag löschen?", isPresented: $loeschen, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task { _ = try? await v.roh("/api/lumi/posts/\(post.id)", methode: "DELETE"); schliessen() }
            }
        }
        .task {
            while !Task.isCancelled {
                if let h: KomHuelle = try? await v.anfrage("/api/lumi/posts/\(post.id)/kommentare") { kom = h.kommentare }
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    @MainActor private func senden() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        struct K: Encodable { let text: String }
        if let h: KomHuelle = try? await v.anfrage("/api/lumi/posts/\(post.id)/kommentare", methode: "POST", body: K(text: t)) {
            kom = h.kommentare; text = ""
        }
    }
}
