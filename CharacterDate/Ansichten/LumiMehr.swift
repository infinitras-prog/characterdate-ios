import SwiftUI
import PhotosUI

// MARK: - Gemeinsamer Stand

@MainActor
enum LumiStand {
    static var ichId: String?
}

struct LumiStory: Decodable, Hashable { let url: String; let text: String; let zeit: Double }

private struct ReelsHuelle: Decodable { let posts: [LumiPost] }
private struct EntdeckenHuelle: Decodable { let posts: [LumiPost]; let hashtags: [[JSONWert]] }

struct LumiMitteilung: Decodable, Identifiable {
    let id: String
    let art: String
    let text: String
    let zeit: Double
    let gelesen: Bool
    let postId: String?
    let konto: LumiKontoKurz?
    let bild: String?
}
private struct MitteilungenHuelle: Decodable { let mitteilungen: [LumiMitteilung]; let ungelesen: Int }

func lumiIstVideo(_ p: String?) -> Bool {
    guard let p else { return false }
    let k = p.lowercased()
    return k.hasSuffix(".mp4") || k.hasSuffix(".mov") || k.hasSuffix(".webm")
}

/// Bild oder Video eines Posts (Videos spielen stumm in Schleife).
struct LumiMedium: View {
    let pfad: String
    var poster: String? = nil
    var body: some View {
        if lumiIstVideo(pfad) { ChatVideo(pfad: pfad) } else { NetzBild(pfad: pfad) }
    }
}

/// Vorschaubild für Raster (bei Reels das Poster).
struct LumiKachel: View {
    let p: LumiPost
    var body: some View {
        Color.clear.aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let m = p.medien.first {
                    if lumiIstVideo(m) { if let po = p.poster { NetzBild(pfad: po) } else { Color(white: 0.1) } } else { NetzBild(pfad: m) }
                } else { Text(p.text).font(.caption2).padding(6) }
            }
            .overlay(alignment: .topTrailing) {
                if p.art == "reel" { Image(systemName: "play.fill").font(.caption).padding(6).shadow(radius: 3) }
            }
            .clipped()
    }
}

// MARK: - Reels (Vollbild, hochwischen)

struct LumiReels: View {
    @Environment(Verbindung.self) private var v
    @Binding var pfad: NavigationPath
    @State private var posts: [LumiPost]?
    @State private var teilen: LumiPost?

    var body: some View {
        Group {
            if let posts {
                if posts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "play.rectangle").font(.system(size: 54, weight: .thin))
                        Text("Noch keine Reels").font(.headline)
                        Text("Reels entstehen im Leerlauf am PC – Charaktere und Creator posten über den Tag.")
                            .font(.footnote).foregroundStyle(IG.grau).multilineTextAlignment(.center)
                    }.padding(40)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(posts) { p in
                                LumiReelKarte(post: p, pfad: $pfad, teilen: { teilen = $0 })
                                    .containerRelativeFrame([.horizontal, .vertical])
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea(edges: .bottom)
                }
            } else { ProgressView().tint(.white) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task { if let h: ReelsHuelle = try? await v.anfrage("/api/lumi/reels") { posts = h.posts } else { posts = [] } }
        .sheet(item: $teilen) { p in LumiTeilen(post: p).presentationDetents([.medium]) }
    }
}

private struct LumiReelKarte: View {
    @Environment(Verbindung.self) private var v
    @State var post: LumiPost
    @Binding var pfad: NavigationPath
    let teilen: (LumiPost) -> Void
    @State private var folge = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if let m = post.medien.first { LumiMedium(pfad: m, poster: post.poster).frame(maxWidth: .infinity, maxHeight: .infinity).clipped() }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button { pfad.append(post.konto.id) } label: {
                            HStack(spacing: 8) { LumiAvatar(k: post.konto, groesse: 32, ring: false); Text(post.konto.name).font(.subheadline.bold()) }
                        }.buttonStyle(.plain)
                        if !(post.ichFolge ?? false) && !folge {
                            Button("Folgen") { Task { await folgen() } }
                                .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 4)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.7)))
                        }
                    }
                    if !post.text.isEmpty { Text(post.text).font(.footnote).lineLimit(3) }
                }
                Spacer()
                VStack(spacing: 18) {
                    Button { Task { await liken() } } label: {
                        VStack(spacing: 3) {
                            Image(systemName: post.geliked ? "heart.fill" : "heart").font(.title2)
                                .foregroundStyle(post.geliked ? Color(red: 1, green: 0.19, blue: 0.25) : .white)
                            Text(Lumi.zahl(post.likes)).font(.caption2)
                        }
                    }
                    Button { pfad.append(post) } label: {
                        VStack(spacing: 3) { Image(systemName: "bubble.right").font(.title2); Text("\(post.kommentare)").font(.caption2) }
                    }
                    Button { teilen(post) } label: { Image(systemName: "paperplane").font(.title2) }
                }
                .buttonStyle(.plain)
            }
            .padding(16).padding(.bottom, 20)
        }
        .onTapGesture(count: 2) { if !post.geliked { Task { await liken() } } }
    }

    @MainActor private func liken() async {
        let an = !post.geliked
        post.geliked = an; post.likes += an ? 1 : -1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        struct A: Encodable { let an: Bool }
        let poster = post.poster
        if var n: LumiPost = try? await v.anfrage("/api/lumi/posts/\(post.id)/like", methode: "POST", body: A(an: an)) {
            if n.poster == nil { n.poster = poster }
            post = n
        }
    }

    @MainActor private func folgen() async {
        folge = true
        struct A: Encodable { let an: Bool }
        _ = try? await v.roh("/api/lumi/konto/\(post.konto.id)/folgen", methode: "POST", body: A(an: true))
    }
}

// MARK: - Entdecken (unter der Suche)

struct LumiEntdecken: View {
    @Environment(Verbindung.self) private var v
    @Binding var pfad: NavigationPath
    @State private var posts: [LumiPost] = []
    @State private var tags: [(String, Int)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.0) { t in
                            (Text("#\(t.0) ") + Text("\(t.1)").foregroundStyle(IG.grau)).font(.footnote)
                                .padding(.horizontal, 12).padding(.vertical, 6).background(IG.feld, in: Capsule())
                        }
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 3), spacing: 1.5) {
                ForEach(posts) { p in Button { pfad.append(p) } label: { LumiKachel(p: p) }.buttonStyle(.plain) }
            }
        }
        .task {
            if let h: EntdeckenHuelle = try? await v.anfrage("/api/lumi/entdecken") {
                posts = h.posts
                tags = h.hashtags.compactMap { z in
                    guard z.count == 2, let t = z[0].text, let n = z[1].zahl else { return nil }
                    return (t, Int(n))
                }
            }
        }
    }
}

// MARK: - Mitteilungen

struct LumiMitteilungen: View {
    @Environment(Verbindung.self) private var v
    @Binding var pfad: NavigationPath
    @State private var liste: [LumiMitteilung]?

    var body: some View {
        List {
            if let liste {
                if liste.isEmpty {
                    Text("Likes, Kommentare und neue Posts von Konten, denen du folgst, erscheinen hier.")
                        .font(.footnote).foregroundStyle(IG.grau).listRowBackground(Color.black)
                }
                ForEach(liste) { m in
                    Button { if let k = m.konto { pfad.append(k.id) } } label: {
                        HStack(spacing: 12) {
                            if let k = m.konto { LumiAvatar(k: k, groesse: 40, ring: false) } else { Image(systemName: "heart").frame(width: 40) }
                            (Text(m.text).font(.footnote) + Text("  " + Lumi.vor(m.zeit)).font(.caption2).foregroundStyle(IG.grau))
                            Spacer()
                            if let b = m.bild { NetzBild(pfad: b).frame(width: 40, height: 40).clipped().clipShape(RoundedRectangle(cornerRadius: 4)) }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(m.gelesen ? Color.black : Color(red: 0.06, green: 0.08, blue: 0.1))
                }
            } else { ProgressView().tint(.white).listRowBackground(Color.black) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Mitteilungen")
        .task {
            if let h: MitteilungenHuelle = try? await v.anfrage("/api/lumi/mitteilungen") { liste = h.mitteilungen } else { liste = [] }
            _ = try? await v.roh("/api/lumi/mitteilungen/gelesen", methode: "POST")
        }
    }
}

// MARK: - Eigener Beitrag

struct LumiErstellen: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    @State private var auswahl: [PhotosPickerItem] = []
    @State private var bilder: [Data] = []
    @State private var text = ""
    @State private var ort = ""
    @State private var laeuft = false
    @State private var fehler: String?
    var fertig: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $auswahl, maxSelectionCount: 6, matching: .images) {
                        if bilder.isEmpty {
                            Label("Fotos auswählen (bis zu 6)", systemImage: "photo.on.rectangle.angled")
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(bilder.indices, id: \.self) { i in
                                        if let u = UIImage(data: bilder[i]) {
                                            Image(uiImage: u).resizable().scaledToFill().frame(width: 80, height: 100).clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: auswahl) { _, neu in
                        Task {
                            var d: [Data] = []
                            for item in neu { if let x = try? await item.loadTransferable(type: Data.self) { d.append(x) } }
                            bilder = d
                        }
                    }
                }
                Section {
                    TextField("Bildunterschrift … (#hashtags gehen auch)", text: $text, axis: .vertical).lineLimit(3...6)
                    TextField("Ort hinzufügen", text: $ort)
                }
                if let fehler { Text(fehler).foregroundStyle(.orange) }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Neuer Beitrag").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { schliessen() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(laeuft ? "…" : "Teilen") { Task { await posten() } }
                        .disabled(laeuft || (bilder.isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @MainActor private func posten() async {
        laeuft = true
        defer { laeuft = false }
        do {
            let jpgs = bilder.compactMap { UIImage(data: $0)?.jpegData(compressionQuality: 0.88) }
            let _: LumiPost = try await v.hochladenMehrere("/api/lumi/posts", dateien: jpgs, feld: "dateien", typ: "image/jpeg",
                                                           felder: ["text": text, "ort": ort])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            fertig()
            schliessen()
        } catch { fehler = error.localizedDescription }
    }
}

// MARK: - Teilen per DM

struct LumiTeilen: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    let post: LumiPost
    @State private var wahl: String?
    @State private var text = ""

    var body: some View {
        VStack(spacing: 14) {
            Text("Teilen").font(.headline).padding(.top, 14)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(v.charaktere.filter { ($0.entwurf ?? 0) == 0 }) { c in
                        Button { wahl = c.id } label: {
                            VStack(spacing: 4) {
                                Avatar(c: c, groesse: 56)
                                    .overlay(Circle().stroke(IG.blau, lineWidth: wahl == c.id ? 3 : 0))
                                Text(c.name).font(.caption2).lineLimit(1)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal)
            }
            HStack {
                TextField("Nachricht schreiben …", text: $text)
                Button("Senden") { Task { await senden() } }.bold().disabled(wahl == nil)
            }
            .padding(12).background(IG.feld, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal).padding(.bottom)
        }
        .background(Color(white: 0.08))
        .preferredColorScheme(.dark)
    }

    @MainActor private func senden() async {
        guard let wahl else { return }
        struct T: Encodable { let char_id: String; let text: String }
        _ = try? await v.roh("/api/lumi/posts/\(post.id)/teilen", methode: "POST", body: T(char_id: wahl, text: text))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        schliessen()
    }
}

// MARK: - Highlights / Storys eines Kontos

struct LumiStoryBlatt: View {
    @Environment(\.dismiss) private var schliessen
    let storys: [LumiStory]
    @State private var i = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if storys.indices.contains(i) {
                NetzBild(pfad: storys[i].url, modus: .fit).ignoresSafeArea()
                VStack {
                    HStack(spacing: 4) {
                        ForEach(storys.indices, id: \.self) { n in
                            Capsule().fill(.white.opacity(n <= i ? 1 : 0.35)).frame(height: 2)
                        }
                    }.padding(.horizontal, 10).padding(.top, 8)
                    Spacer()
                    if !storys[i].text.isEmpty {
                        Text(storys[i].text).font(.callout).padding().frame(maxWidth: .infinity)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if i + 1 < storys.count { i += 1 } else { schliessen() } }
        .task(id: i) {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { if i + 1 < storys.count { i += 1 } else { schliessen() } }
        }
    }
}

struct LumiHighlights: View {
    let highlights: [LumiStory]
    let zeigen: ([LumiStory]) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(highlights, id: \.self) { h in
                    Button { zeigen([h]) } label: {
                        VStack(spacing: 4) {
                            NetzBild(pfad: h.url).frame(width: 62, height: 62).clipShape(Circle())
                                .padding(3).overlay(Circle().stroke(Color(white: 0.3)))
                            Text(Date(timeIntervalSince1970: h.zeit).formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_DE"))))
                                .font(.caption2)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }
    }
}
