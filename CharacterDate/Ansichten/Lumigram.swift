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

// MARK: - Hauptansicht

struct LumigramAnsicht: View {
    @Environment(Verbindung.self) private var v
    var chatOeffnen: (Charakter) -> Void = { _ in }
    @State private var ich: LumiKonto?
    @State private var geladen = false
    @State private var tab = 0
    @State private var pfad = NavigationPath()

    var body: some View {
        NavigationStack(path: $pfad) {
            Group {
                if !geladen {
                    ProgressView().tint(.white)
                } else if ich == nil {
                    LumiAnmelden { await laden() }
                } else {
                    VStack(spacing: 0) {
                        Picker("", selection: $tab) {
                            Image(systemName: "house.fill").tag(0)
                            Image(systemName: "magnifyingglass").tag(1)
                            Image(systemName: "person.crop.circle").tag(2)
                        }
                        .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
                        switch tab {
                        case 0: LumiFeed(pfad: $pfad)
                        case 1: LumiSuche(pfad: $pfad)
                        default: if let ich { LumiKontoAnsicht(id: ich.id, pfad: $pfad, chatOeffnen: chatOeffnen) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Hintergrund())
            .toolbar { ToolbarItem(placement: .principal) { Lumi.logo } }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { kid in LumiKontoAnsicht(id: kid, pfad: $pfad, chatOeffnen: chatOeffnen) }
            .navigationDestination(for: LumiPost.self) { p in LumiPostAnsicht(post: p, pfad: $pfad) }
        }
        .task { await laden() }
    }

    @MainActor private func laden() async {
        if let h: KontoHuelle = try? await v.anfrage("/api/lumi/ich") { ich = h.konto }
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

    var body: some View {
        ScrollView {
            if let posts {
                if posts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.largeTitle)
                        Text("Noch niemand im Feed").font(.headline)
                        Text("Frag deine Charaktere im Chat nach ihrem Lumigram-Namen und such sie dann.")
                            .font(.footnote).foregroundStyle(Farbe.text3).multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    LazyVStack(spacing: 20) {
                        ForEach(posts) { p in LumiPostKarte(post: p, pfad: $pfad) }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                ProgressView().tint(.white).padding(60)
            }
        }
        .refreshable { await laden() }
        .task { await laden() }
    }

    @MainActor private func laden() async {
        if let f: FeedHuelle = try? await v.anfrage("/api/lumi/feed") { posts = f.posts } else if posts == nil { posts = [] }
    }
}

struct LumiAvatar: View {
    let k: LumiKontoKurz
    var groesse: CGFloat = 34
    var body: some View {
        ZStack {
            if let a = k.avatar { NetzBild(pfad: a) } else {
                Circle().fill(Farbe.verlauf)
                Text(String(k.name.prefix(1)).uppercased()).font(.system(size: groesse * 0.42, weight: .bold))
            }
        }
        .frame(width: groesse, height: groesse).clipShape(Circle())
        .overlay(Circle().stroke(Farbe.rose, lineWidth: 1.5).padding(-2.5))
    }
}

struct LumiPostKarte: View {
    @Environment(Verbindung.self) private var v
    @State var post: LumiPost
    @Binding var pfad: NavigationPath
    @State private var herz = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { pfad.append(post.konto.id) } label: {
                HStack(spacing: 10) {
                    LumiAvatar(k: post.konto)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.konto.name).font(.subheadline.bold())
                        if !post.ort.isEmpty { Label(post.ort, systemImage: "mappin").font(.caption2).foregroundStyle(Farbe.text3) }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain).padding(.horizontal, 12)
            ZStack {
                if let m = post.medien.first {
                    NetzBild(pfad: m).aspectRatio(4 / 5, contentMode: .fill).frame(maxWidth: .infinity).clipped()
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
                    Image(systemName: post.geliked ? "heart.fill" : "heart").font(.title3)
                        .foregroundStyle(post.geliked ? Color(red: 1, green: 0.23, blue: 0.42) : .white)
                        .symbolEffect(.bounce, value: post.geliked)
                }
                Button { pfad.append(post) } label: { Image(systemName: "bubble.right").font(.title3) }
                Spacer()
            }
            .buttonStyle(.plain).padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Lumi.zahl(post.likes)) „Gefällt mir“-Angaben").font(.footnote.bold())
                if !post.text.isEmpty { (Text(post.konto.name).bold() + Text(" " + post.text)).font(.footnote) }
                if post.kommentare > 0 {
                    Button("Alle \(post.kommentare) Kommentare ansehen") { pfad.append(post) }
                        .font(.footnote).foregroundStyle(Farbe.text3)
                }
                Text(Lumi.vor(post.zeit)).font(.caption2).foregroundStyle(Farbe.text3)
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 10)
    }

    @MainActor private func liken(_ an: Bool) async {
        let alt = post
        post.geliked = an
        post.likes += an == alt.geliked ? 0 : (an ? 1 : -1)
        struct A: Encodable { let an: Bool }
        if let n: LumiPost = try? await v.anfrage("/api/lumi/posts/\(post.id)/like", methode: "POST", body: A(an: an)) { post = n }
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
                Image(systemName: "magnifyingglass").foregroundStyle(Farbe.text2)
                TextField("@nutzername – genau wie sie ihn verraten hat", text: $q)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .onSubmit { Task { await suchen() } }
            }
            .padding(12).glas(14)
            Button("Suchen") { Task { await suchen() } }.buttonStyle(HauptKnopf()).disabled(q.count < 3)
            if nichts { Text("Kein Konto mit genau diesem Namen.").font(.footnote).foregroundStyle(.orange) }
            Spacer()
        }
        .padding(20)
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

    var body: some View {
        ScrollView {
            if let k {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 24) {
                        LumiAvatar(k: LumiKontoKurz(id: k.id, name: k.name, anzeige: k.anzeige, avatar: k.avatar), groesse: 84)
                        HStack(spacing: 22) {
                            zahl(k.postsAnzahl, "Beiträge"); zahl(k.follower, "Follower"); zahl(k.folgt, "Gefolgt")
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k.anzeige.isEmpty ? k.name : k.anzeige).font(.subheadline.bold())
                        Text("@" + k.name).font(.caption).foregroundStyle(Farbe.text3)
                        if !k.bio.isEmpty { Text(k.bio).font(.footnote).padding(.top, 4) }
                    }
                    if !k.istIch {
                        HStack(spacing: 8) {
                            Button { Task { await folgen(!k.ichFolge) } } label: {
                                Text(k.ichFolge ? "Gefolgt" : k.folgtMir ? "Zurückfolgen" : "Folgen").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(HauptKnopf(farbe: k.ichFolge ? AnyShapeStyle(Color.white.opacity(0.12)) : AnyShapeStyle(Farbe.verlauf)))
                            if let cid = k.charId, let c = v.charaktere.first(where: { $0.id == cid }) {
                                Button { chatOeffnen(c) } label: { Text("Nachricht").frame(maxWidth: .infinity) }
                                    .buttonStyle(HauptKnopf(farbe: AnyShapeStyle(Color.white.opacity(0.12))))
                            }
                        }
                        if k.folgtMir { Text("folgt dir").font(.caption2).foregroundStyle(Farbe.text3) }
                    }
                    Divider().overlay(Farbe.linie)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                        ForEach(k.posts) { p in
                            Button { pfad.append(p) } label: {
                                Color.clear.aspectRatio(4 / 5, contentMode: .fit)
                                    .overlay { if let m = p.medien.first { NetzBild(pfad: m) } else { Text(p.text).font(.caption2).padding(6) } }
                                    .clipped()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            } else {
                ProgressView().tint(.white).padding(60)
            }
        }
        .background(Hintergrund())
        .refreshable { await laden() }
        .task { await laden() }
    }

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
                                Text(Lumi.vor(c.zeit)).font(.caption2).foregroundStyle(Farbe.text3)
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
        .background(Hintergrund())
        .navigationTitle("Beitrag").navigationBarTitleDisplayMode(.inline)
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
