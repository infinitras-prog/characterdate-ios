import SwiftUI

// MARK: - Daten

struct TankProfil: Decodable, Identifiable, Equatable {
    let id: String
    var name: String = ""
    var alter: Int?
    var beruf: String?
    var wohnort: String?
    var bio: String?
    var leidenschaften: [String] = []
    var sucht: String?
    var sternzeichen: String?
    var groesseCm: Int?
    var entfernungKm: Int?
    var aktivVorMin: Int?
    var verifiziert: Bool = false
    var fotos: [String] = []
    var stimme: String?

    enum CodingKeys: String, CodingKey {
        case id, name, alter, beruf, wohnort, bio, leidenschaften, sucht, sternzeichen, groesseCm, entfernungKm,
             aktivVorMin, verifiziert, fotos, stimme
    }

    init(id: String, name: String, alter: Int?, foto: String?) {
        self.id = id; self.name = name; self.alter = alter; self.fotos = foto.map { [$0] } ?? []
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        alter = Self.zahl(c, .alter)
        beruf = try? c.decodeIfPresent(String.self, forKey: .beruf)
        wohnort = try? c.decodeIfPresent(String.self, forKey: .wohnort)
        bio = try? c.decodeIfPresent(String.self, forKey: .bio)
        leidenschaften = ((try? c.decodeIfPresent([String].self, forKey: .leidenschaften)) ?? nil) ?? []
        sucht = try? c.decodeIfPresent(String.self, forKey: .sucht)
        sternzeichen = try? c.decodeIfPresent(String.self, forKey: .sternzeichen)
        groesseCm = Self.zahl(c, .groesseCm)
        entfernungKm = Self.zahl(c, .entfernungKm)
        aktivVorMin = Self.zahl(c, .aktivVorMin)
        verifiziert = ((try? c.decodeIfPresent(Bool.self, forKey: .verifiziert)) ?? nil) ?? false
        fotos = ((try? c.decodeIfPresent([String].self, forKey: .fotos)) ?? nil) ?? []
        stimme = try? c.decodeIfPresent(String.self, forKey: .stimme)
    }

    /// Zahlen kommen vom Sprachmodell mal als Zahl, mal als Text („25“, „168 cm“).
    private static func zahl(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int? {
        if let i = try? c.decodeIfPresent(Int.self, forKey: k) { return i }
        if let f = try? c.decodeIfPresent(Double.self, forKey: k) { return Int(f) }
        if let s = try? c.decodeIfPresent(String.self, forKey: k) { return Int(s.filter(\.isNumber)) }
        return nil
    }

    var aktivText: String? {
        guard let m = aktivVorMin else { return nil }
        if m < 15 { return "Gerade aktiv" }
        if m < 60 { return "Vor \(m) Min. aktiv" }
        if m < 1440 { return "Vor \(m / 60) Std. aktiv" }
        return nil
    }
}

private struct TankStapel: Decodable {
    var profile: [TankProfil] = []
    var imTank: Int = 0
    var ziel: Int = 50
    var erzeugtGerade: Bool = false
    var schritt: String?
    var superLikesUebrig: Int = 0
    var voll: Bool?
    var manuell: TankStatus.Manuell?
}

struct TankLM: Decodable {
    struct Like: Decodable, Identifiable { let id: String; let foto: String?; let zeit: Double }
    struct Match: Decodable, Identifiable { let id: String; let charId: String?; let name: String; let alter: Int?; let foto: String?; let zeit: Double?; let neu: Bool }
    let likes: [Like]
    let matches: [Match]
    let ausstehend: Int
}

private struct SwipeAntwort: Decodable {
    var wartet: Bool?
    var match: Bool = false
    var charId: String?
    var `super`: Bool?
}

private struct ZurueckAntwort: Decodable { var profil: TankProfil }

enum SwipeRichtung: String { case links, rechts, `super` }

// MARK: - Ansicht

struct SwipeAnsicht: View {
    @Environment(Verbindung.self) private var v
    var chatOeffnen: (Charakter) -> Void = { _ in }

    @State private var stapel: [TankProfil] = []
    @State private var info = TankStapel()
    @State private var laedt = true
    @State private var verschub: CGSize = .zero
    @State private var wegfliegen: SwipeRichtung?
    @State private var match: (profil: TankProfil, char: Charakter?)?
    @State private var fehler: String?
    @State private var einstellungen = false
    @State private var tankOffen = false
    @State private var letzteRichtung: SwipeRichtung?
    @State private var boost = false
    @State private var reiter = 0
    @State private var lm: TankLM?
    @State private var abo: UUID?

    var body: some View {
        VStack(spacing: 14) {
            kopf
            reiterLeiste
            if reiter != 0 {
                LikesMatchesAnsicht(art: reiter, lm: lm, vorziehen: { id in
                    Task {
                        _ = try? await v.roh("/api/tank/\(id)/vorziehen", methode: "POST")
                        stapel = []; await laden(still: true); withAnimation { reiter = 0 }
                    }
                }, chat: { cid in if let c = v.charaktere.first(where: { $0.id == cid }) { chatOeffnen(c) } })
            } else {
            ZStack {
                if stapel.isEmpty {
                    leer
                } else {
                    ForEach(Array(stapel.prefix(3).enumerated().reversed()), id: \.element.id) { i, p in
                        karte(p, index: i)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            knoepfe.padding(.bottom, 10)
            }
        }
        .background(Hintergrund())
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if let m = match {
                MatchFeier(profil: m.profil, char: m.char, schliessen: { withAnimation { match = nil } },
                           schreiben: { if let c = m.char { match = nil; chatOeffnen(c) } })
                    .transition(.opacity.combined(with: .scale(scale: 1.06)))
            }
        }
        .overlay(alignment: .top) {
            if let fehler {
                Text(fehler).font(.footnote).padding(10).glas(14).padding(.top, 60).padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task { try? await Task.sleep(for: .seconds(3.5)); withAnimation { self.fehler = nil } }
            }
        }
        .sheet(isPresented: $einstellungen) { TankEinstellungen().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $tankOffen) {
            NavigationStack {
                ScrollView { TankKarte().padding() }
                    .background(Hintergrund())
                    .navigationTitle("Dein Profil-Tank").navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
            .onDisappear { Task { await laden(still: true) } }
        }
        .task { await laden() }
        .task {
            await lmLaden()
            abo = v.abonnieren { e in
                Task { @MainActor in
                    if e.typ == "tank_like" {
                        await lmLaden()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        fehler = "Jemand hat dich geliked 💛"
                    }
                    if e.typ == "neues_match", match == nil, let cid = e.charId {
                        await lmLaden(); await v.neuLaden()
                        if let m = lm?.matches.first(where: { $0.charId == cid }) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                match = (TankProfil(id: m.id, name: m.name, alter: m.alter, foto: m.foto), v.charaktere.first { $0.id == cid })
                            }
                        }
                    }
                }
            }
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(20)); await lmLaden() }
        }
        .task {
            // Tank füllt sich im Hintergrund: ab und zu nachschauen
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(stapel.isEmpty ? 8 : 30))
                if stapel.count < 3 { await laden(still: true) }
            }
        }
    }

    private var tankStand: TankStatus {
        TankStatus(imTank: info.imTank, ziel: info.ziel, erzeugtGerade: info.erzeugtGerade, schritt: info.schritt,
                   voll: info.voll, manuell: info.manuell, superLikesUebrig: info.superLikesUebrig)
    }

    private var reiterLeiste: some View {
        HStack(spacing: 4) {
            reiterKnopf(0, "Entdecken", nil, false)
            reiterKnopf(1, "Likes", lm.map { $0.likes.count }, true)
            reiterKnopf(2, "Matches", lm.map { $0.matches.filter(\.neu).count }, false)
        }
        .padding(4).background(.white.opacity(0.06), in: Capsule())
        .padding(.horizontal, 16)
    }

    private func reiterKnopf(_ i: Int, _ t: String, _ zahl: Int?, _ gold: Bool) -> some View {
        Button { withAnimation(.spring(duration: 0.3)) { reiter = i } } label: {
            HStack(spacing: 5) {
                Text(t).font(.subheadline.weight(.semibold))
                if let zahl, zahl > 0 {
                    Text("\(zahl)").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(gold ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.91, green: 0.69, blue: 0.29), Color(red: 0.96, green: 0.82, blue: 0.48)], startPoint: .leading, endPoint: .trailing))
                                         : AnyShapeStyle(Color(red: 0.99, green: 0.15, blue: 0.48)), in: Capsule())
                        .foregroundStyle(gold ? Color(red: 0.23, green: 0.14, blue: 0) : .white)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(reiter == i ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.99, green: 0.15, blue: 0.48), Color(red: 1, green: 0.38, blue: 0.21)], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.clear), in: Capsule())
            .foregroundStyle(reiter == i ? .white : Farbe.text2)
        }
        .buttonStyle(.plain)
    }

    @MainActor private func lmLaden() async { if let l: TankLM = try? await v.anfrage("/api/tank/likes") { lm = l } }

    // MARK: Teile

    private var kopf: some View {
        HStack {
            Image(systemName: "flame.fill").font(.title2)
                .foregroundStyle(LinearGradient(colors: [.orange, Farbe.rose], startPoint: .bottom, endPoint: .top))
            Text("Swipe").font(.title2.bold())
            Spacer()
            Button { tankOffen = true } label: {
                HStack(spacing: 6) {
                    TankHerz(stand: tankStand, groesse: 24, lampen: false)
                    Text("\(info.imTank)/\(info.ziel)").font(.caption.monospacedDigit().bold())
                    Lampe(farbe: Color(red: 0.96, green: 0.72, blue: 0.38), an: tankStand.fuellt, blinkt: tankStand.pausiert, text: "")
                    Lampe(farbe: Farbe.mint, an: tankStand.istVoll, blinkt: false, text: "")
                }
                .padding(.horizontal, 10).padding(.vertical, 5).glas(14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tank: \(info.imTank) von \(info.ziel) – antippen zum Füllen")
            Button { einstellungen = true } label: {
                Image(systemName: "slider.horizontal.3").font(.body.bold()).frame(width: 36, height: 36).glas(18)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var leer: some View {
        VStack(spacing: 16) {
            if laedt {
                ProgressView().tint(.white)
            } else {
                ZStack {
                    ForEach(0..<3) { i in
                        Circle().stroke(Farbe.rose.opacity(0.5 - Double(i) * 0.15), lineWidth: 2)
                            .frame(width: 90 + CGFloat(i) * 50, height: 90 + CGFloat(i) * 50)
                            .modifier(Pulsieren(verzoegerung: Double(i) * 0.4))
                    }
                    Image(systemName: "flame.fill").font(.system(size: 40)).foregroundStyle(Farbe.verlauf)
                }
                .frame(height: 200)
                Text("Gerade niemand Neues in deiner Nähe").font(.headline)
                Text(info.erzeugtGerade
                     ? "Neue Profile entstehen gerade\(info.schritt.map { " – \($0)" } ?? "") …"
                     : "Neue Profile entstehen, sobald dein PC nichts anderes zu tun hat (Fotos, Stimme, Steckbrief mit Qualitätsprüfung).")
                    .font(.footnote).foregroundStyle(Farbe.text2).multilineTextAlignment(.center).padding(.horizontal, 30)
            }
        }
    }

    private var knoepfe: some View {
        HStack(spacing: 18) {
            RundKnopf(symbol: "arrow.uturn.backward", farbe: .yellow, groesse: 48) { Task { await zurueck() } }
                .disabled(letzteRichtung == nil)
            RundKnopf(symbol: "xmark", farbe: Color(red: 1, green: 0.32, blue: 0.42), groesse: 62) { werfen(.links) }
            RundKnopf(symbol: "star.fill", farbe: Color(red: 0.25, green: 0.7, blue: 1), groesse: 48,
                      zaehler: info.superLikesUebrig) { werfen(.super) }
                .disabled(info.superLikesUebrig <= 0)
            RundKnopf(symbol: "heart.fill", farbe: Color(red: 0.2, green: 0.9, blue: 0.6), groesse: 62) { werfen(.rechts) }
            RundKnopf(symbol: "bolt.fill", farbe: Farbe.violett, groesse: 48) {
                withAnimation(.spring) { boost.toggle() }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                fehler = boost ? "Boost aktiv – dein Profil wird 30 Minuten lang öfter gezeigt." : nil
            }
            .overlay { if boost { Circle().stroke(Farbe.violett, lineWidth: 2).modifier(Pulsieren(verzoegerung: 0)) } }
        }
        .disabled(stapel.isEmpty || wegfliegen != nil)
        .opacity(stapel.isEmpty ? 0.5 : 1)
    }

    @ViewBuilder
    private func karte(_ p: TankProfil, index i: Int) -> some View {
        let oben = i == 0
        let breite: CGFloat = 420
        let ziel: CGSize = {
            switch wegfliegen {
            case .links?: return CGSize(width: -breite * 1.6, height: verschub.height + 60)
            case .rechts?: return CGSize(width: breite * 1.6, height: verschub.height + 60)
            case .super?: return CGSize(width: 0, height: -1100)
            case nil: return verschub
            }
        }()
        let x = oben ? ziel.width : 0
        let y = oben ? ziel.height : CGFloat(i) * 10
        let fortschrittX = max(-1, min(1, x / 140))
        let fortschrittY = max(0, min(1, -y / 160))
        ProfilKarte(p: p, aktiv: oben,
                    like: oben ? max(0, Double(fortschrittX)) : 0,
                    nope: oben ? max(0, Double(-fortschrittX)) : 0,
                    superLike: oben ? Double(fortschrittY) * (abs(fortschrittX) < 0.4 ? 1 : 0) : 0)
            .scaleEffect(oben ? 1 : 1 - CGFloat(i) * 0.04 + (abs(fortschrittX) * 0.04))
            .offset(x: x, y: y)
            .rotationEffect(.degrees(oben ? Double(x / 18) : 0), anchor: .bottom)
            .allowsHitTesting(oben)
            .gesture(oben ? ziehen : nil)
            .zIndex(Double(10 - i))
    }

    private var ziehen: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                guard wegfliegen == nil else { return }
                let alt = verschub
                verschub = g.translation
                // spürbares Einrasten an der Schwelle
                if (abs(alt.width) < 110) != (abs(verschub.width) < 110) || (alt.height > -130) != (verschub.height > -130) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .onEnded { g in
                let vx = g.predictedEndTranslation.width
                if g.translation.width > 110 || vx > 420 { werfen(.rechts) }
                else if g.translation.width < -110 || vx < -420 { werfen(.links) }
                else if g.translation.height < -130 && abs(g.translation.width) < 90, info.superLikesUebrig > 0 { werfen(.super) }
                else { withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) { verschub = .zero } }
            }
    }

    // MARK: Aktionen

    private func werfen(_ r: SwipeRichtung) {
        guard let p = stapel.first, wegfliegen == nil else { return }
        UIImpactFeedbackGenerator(style: r == .super ? .heavy : .medium).impactOccurred()
        Abspieler.shared.stopp()
        withAnimation(.easeIn(duration: 0.28)) { wegfliegen = r }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            stapel.removeFirst()
            verschub = .zero
            wegfliegen = nil
            letzteRichtung = r
            await swipen(p, r)
            if stapel.count < 3 { await laden(still: true) }
        }
    }

    @MainActor private func swipen(_ p: TankProfil, _ r: SwipeRichtung) async {
        struct K: Encodable { let richtung: String }
        do {
            let a: SwipeAntwort = try await v.anfrage("/api/tank/\(p.id)/swipe", methode: "POST", body: K(richtung: r.rawValue), zeit: 90)
            if r == .super { info.superLikesUebrig = max(0, info.superLikesUebrig - 1) }
            info.imTank = max(0, info.imTank - 1)
            if a.wartet == true {
                fehler = "Like an \(p.name) geschickt 💛 – jetzt ist sie dran."
                await lmLaden()
            }
            if a.match {
                await v.neuLaden()
                let c = v.charaktere.first { $0.id == a.charId }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { match = (p, c) }
                letzteRichtung = nil                       // ein Match lässt sich nicht zurückholen
            }
        } catch {
            fehler = error.localizedDescription
        }
    }

    @MainActor private func zurueck() async {
        do {
            let a: ZurueckAntwort = try await v.anfrage("/api/tank/zurueck", methode: "POST")
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                stapel.removeAll { $0.id == a.profil.id }
                stapel.insert(a.profil, at: 0)
            }
            letzteRichtung = nil
            info.imTank += 1
        } catch { fehler = error.localizedDescription }
    }

    @MainActor private func laden(still: Bool = false) async {
        if !still { laedt = true }
        defer { laedt = false }
        guard let s: TankStapel = try? await v.anfrage("/api/tank/stapel?n=8") else { return }
        info = s
        let schon = Set(stapel.map(\.id))
        let neu = s.profile.filter { !schon.contains($0.id) }
        if !neu.isEmpty { withAnimation(.spring) { stapel.append(contentsOf: neu) } }
    }
}

// MARK: - Karte

private struct ProfilKarte: View {
    @Environment(Verbindung.self) private var v
    let p: TankProfil
    let aktiv: Bool
    let like: Double
    let nope: Double
    let superLike: Double
    @State private var foto = 0
    @State private var offen = false
    private var spieler: Abspieler { Abspieler.shared }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                // Fotos (links/rechts tippen wie bei Tinder)
                ZStack {
                    if p.fotos.isEmpty { Rectangle().fill(Farbe.verlauf) }
                    ForEach(Array(p.fotos.enumerated()), id: \.offset) { i, f in
                        NetzBild(pfad: f).opacity(i == foto ? 1 : 0)
                    }
                }
                .frame(width: g.size.width, height: g.size.height).clipped()
                .contentShape(Rectangle())
                .onTapGesture { ort in
                    guard p.fotos.count > 1 else { return }
                    let neu = ort.x < g.size.width / 2 ? foto - 1 : foto + 1
                    if neu < 0 || neu >= p.fotos.count {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
                    } else {
                        withAnimation(.easeOut(duration: 0.15)) { foto = neu }
                    }
                }
                // Abschnitte oben
                VStack {
                    HStack(spacing: 4) {
                        ForEach(0..<max(1, p.fotos.count), id: \.self) { i in
                            Capsule().fill(.white.opacity(i == foto ? 0.95 : 0.35)).frame(height: 4)
                        }
                    }
                    .padding(.horizontal, 10).padding(.top, 8)
                    Spacer()
                }
                // Verlauf + Text
                LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.88)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                beschreibung.padding(16)
                // Stempel
                stempel("LIKE", farbe: Color(red: 0.2, green: 0.9, blue: 0.6), winkel: -18, wert: like)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(28)
                stempel("NOPE", farbe: Color(red: 1, green: 0.32, blue: 0.42), winkel: 18, wert: nope)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(28)
                stempel("SUPER\nLIKE", farbe: Color(red: 0.25, green: 0.7, blue: 1), winkel: -8, wert: superLike)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).padding(.bottom, 120)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(aktiv ? 0.45 : 0.2), radius: aktiv ? 18 : 8, y: 8)
        }
        .onChange(of: aktiv) { _, a in if !a { offen = false } }
    }

    private var beschreibung: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let a = p.aktivText {
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text(a).font(.caption.bold())
                }
                .padding(.horizontal, 8).padding(.vertical, 3).background(.black.opacity(0.35), in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.name).font(.system(size: 30, weight: .heavy))
                if let a = p.alter { Text("\(a)").font(.system(size: 26, weight: .regular)) }
                if p.verifiziert {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(red: 0.25, green: 0.7, blue: 1)).font(.title3)
                }
                Spacer()
                if let s = p.stimme {
                    Button { Task { await spieler.umschalten(s, v: v) } } label: {
                        Image(systemName: spieler.aktuell == s ? "pause.fill" : "waveform")
                            .font(.body.bold()).frame(width: 38, height: 38).background(.white.opacity(0.22), in: Circle())
                    }
                    .accessibilityLabel("Stimme anhören")
                }
                Button { withAnimation(.spring(response: 0.35)) { offen.toggle() } } label: {
                    Image(systemName: offen ? "chevron.down" : "info").font(.body.bold())
                        .frame(width: 38, height: 38).background(.white.opacity(0.22), in: Circle())
                }
                .accessibilityLabel("Profil ansehen")
            }
            Group {
                if let b = p.beruf { Label(b, systemImage: "briefcase") }
                if let w = p.wohnort {
                    Label(w + (p.entfernungKm.map { " · \($0) km entfernt" } ?? ""), systemImage: "mappin.and.ellipse")
                }
            }
            .font(.subheadline).foregroundStyle(.white.opacity(0.9))
            if offen {
                VStack(alignment: .leading, spacing: 10) {
                    if let b = p.bio, !b.isEmpty { Text(b).font(.subheadline) }
                    if let s = p.sucht {
                        HStack(spacing: 6) { Text("👀"); Text("Sucht: ").bold() + Text(s) }.font(.footnote)
                            .padding(8).background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    }
                    HStack(spacing: 8) {
                        if let g = p.groesseCm { Merkmal(symbol: "ruler", text: "\(g) cm") }
                        if let s = p.sternzeichen { Merkmal(symbol: "sparkles", text: s) }
                    }
                    if !p.leidenschaften.isEmpty {
                        FlussLayout(abstand: 6) {
                            ForEach(p.leidenschaften, id: \.self) { l in
                                Text(l).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                                    .overlay(Capsule().stroke(.white.opacity(0.5)))
                            }
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !p.leidenschaften.isEmpty {
                HStack(spacing: 6) {
                    ForEach(p.leidenschaften.prefix(3), id: \.self) { l in
                        Text(l).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stempel(_ t: String, farbe: Color, winkel: Double, wert: Double) -> some View {
        Text(t).font(.system(size: 40, weight: .black)).multilineTextAlignment(.center)
            .foregroundStyle(farbe)
            .padding(.horizontal, 12).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(farbe, lineWidth: 5))
            .rotationEffect(.degrees(winkel))
            .scaleEffect(1.25 - 0.25 * wert)
            .opacity(wert)
            .allowsHitTesting(false)
    }
}

private struct Merkmal: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 5)
            .background(.white.opacity(0.16), in: Capsule())
    }
}

/// Zeilenumbruch-Layout für Leidenschaften.
private struct FlussLayout: Layout {
    var abstand: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breite = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, zeile: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x + g.width > breite, x > 0 { x = 0; y += zeile + abstand; zeile = 0 }
            x += g.width + abstand; zeile = max(zeile, g.height)
        }
        return CGSize(width: breite, height: y + zeile)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, zeile: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x + g.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += zeile + abstand; zeile = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(g))
            x += g.width + abstand; zeile = max(zeile, g.height)
        }
    }
}

private struct RundKnopf: View {
    let symbol: String
    let farbe: Color
    let groesse: CGFloat
    var zaehler: Int? = nil
    let aktion: () -> Void
    @State private var gedrueckt = false
    @Environment(\.isEnabled) private var an

    var body: some View {
        Button(action: aktion) {
            Image(systemName: symbol).font(.system(size: groesse * 0.42, weight: .bold))
                .foregroundStyle(farbe)
                .frame(width: groesse, height: groesse)
                .background(Circle().fill(Farbe.grund.opacity(0.85)))
                .overlay(Circle().stroke(farbe.opacity(0.55), lineWidth: 1.5))
                .shadow(color: farbe.opacity(0.35), radius: 10)
                .overlay(alignment: .topTrailing) {
                    if let z = zaehler {
                        Text("\(z)").font(.caption2.bold()).padding(4).background(farbe, in: Circle()).foregroundStyle(.white)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(Federnd())
        .opacity(an ? 1 : 0.4)
    }
}

private struct Federnd: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

private struct Pulsieren: ViewModifier {
    let verzoegerung: Double
    @State private var an = false
    func body(content: Content) -> some View {
        content.scaleEffect(an ? 1.15 : 0.9).opacity(an ? 0.2 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(verzoegerung)) { an = true }
            }
    }
}

// MARK: - Match-Feier

private struct MatchFeier: View {
    let profil: TankProfil
    let char: Charakter?
    let schliessen: () -> Void
    let schreiben: () -> Void
    @State private var zu = false
    @State private var konfetti = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.55)).ignoresSafeArea()
                .onTapGesture(perform: schliessen)
            // Herzen steigen auf
            ForEach(0..<18, id: \.self) { i in
                Image(systemName: "heart.fill")
                    .font(.system(size: CGFloat(12 + (i * 7) % 22)))
                    .foregroundStyle(i % 2 == 0 ? Farbe.rose : Farbe.violett)
                    .offset(x: CGFloat((i * 53) % 340) - 170, y: konfetti ? -520 : 460)
                    .opacity(konfetti ? 0 : 0.9)
                    .animation(.easeOut(duration: 2.2 + Double(i % 5) * 0.3).delay(Double(i) * 0.06), value: konfetti)
            }
            VStack(spacing: 22) {
                Text("It's a Match!")
                    .font(.system(size: 46, weight: .black, design: .rounded).italic())
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.4, green: 1, blue: 0.75), Farbe.rose],
                                                    startPoint: .leading, endPoint: .trailing))
                    .scaleEffect(zu ? 1 : 0.3).opacity(zu ? 1 : 0)
                Text("Du und \(profil.name) habt euch gegenseitig geliked.").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                ZStack {
                    Circle().fill(Farbe.verlauf).frame(width: 190, height: 190).blur(radius: 30).opacity(0.7)
                    NetzBild(pfad: profil.fotos.first).frame(width: 170, height: 170).clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 4))
                        .rotationEffect(.degrees(zu ? 0 : -25)).scaleEffect(zu ? 1 : 0.5)
                }
                Button(action: schreiben) {
                    Label("Nachricht schreiben", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(HauptKnopf()).disabled(char == nil).padding(.horizontal, 36)
                Button("Weiter swipen", action: schliessen).font(.headline).foregroundStyle(.white.opacity(0.85))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { zu = true }
            konfetti = true
        }
    }
}

// MARK: - Einstellungen für den Tank

struct TankEinstellungen: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    @State private var e = HandyEinstellungen()

    var body: some View {
        NavigationStack {
            Form {
                Section { TankKarte() }
                if e.geladen {
                    Section {
                        Toggle("Profile im Hintergrund erzeugen", isOn: Binding(
                            get: { e.wert("tank.aktiv", true) }, set: { e.setzen("tank.aktiv", $0, v) })).tint(Farbe.rose)
                        Stepper("Tank-Größe: \(e.wert("tank.groesse", 50))", value: Binding(
                            get: { e.wert("tank.groesse", 50) }, set: { e.setzen("tank.groesse", $0, v) }), in: 10...100, step: 5)
                    } footer: { Text("Neue Profile entstehen nur, wenn dein PC sonst nichts zu tun hat – sobald du etwas machst, pausiert es.") }
                    Section("Ich suche") {
                        LabeledContent("Geschlecht", value: "Frauen")
                        LabeledContent("Männer / beide") { Text("folgt").foregroundStyle(Farbe.text3) }
                        let von = e.wert("tank.alter_von", 18), bis = e.wert("tank.alter_bis", 25)
                        Stepper("Alter ab \(von)", value: Binding(get: { von }, set: { e.setzen("tank.alter_von", min($0, bis), v) }), in: 18...60)
                        Stepper("Alter bis \(bis >= 60 ? "60+" : "\(bis)")", value: Binding(
                            get: { bis }, set: { e.setzen("tank.alter_bis", max($0, von), v) }), in: 18...60)
                    }
                } else {
                    ProgressView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Hintergrund())
            .navigationTitle("Swipe-Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { schliessen() } } }
            .task { await e.laden(v) }
        }
    }
}


/// Likes (verschwommen – wer dich mag, siehst du erst im Stapel) und Matches (offen, Antippen → Chat).
struct LikesMatchesAnsicht: View {
    let art: Int
    let lm: TankLM?
    let vorziehen: (String) -> Void
    let chat: (String) -> Void
    private let spalten = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            if let lm {
                VStack(alignment: .leading, spacing: 10) {
                    if art == 1 {
                        Text(lm.likes.isEmpty ? "Noch keine Likes" : "\(lm.likes.count) \(lm.likes.count == 1 ? "Person mag" : "Leute mögen") dich")
                            .font(.title3.bold())
                        Text("Wer dich geliked hat, bleibt verschwommen – bis ihr euch im Stapel begegnet. Wischst du sie nach rechts, ist es sofort ein Match."
                             + (lm.ausstehend > 0 ? " Du wartest noch auf \(lm.ausstehend) Antwort\(lm.ausstehend == 1 ? "" : "en")." : ""))
                            .font(.footnote).foregroundStyle(Farbe.text2)
                        LazyVGrid(columns: spalten, spacing: 10) {
                            ForEach(lm.likes) { l in
                                Button { vorziehen(l.id) } label: {
                                    Color.clear.aspectRatio(3 / 4, contentMode: .fit)
                                        .overlay { if let f = l.foto { NetzBild(pfad: f).blur(radius: 22).scaleEffect(1.15) } }
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: "heart.fill").font(.caption.bold()).padding(8)
                                                .background(LinearGradient(colors: [Color(red: 0.91, green: 0.69, blue: 0.29), Color(red: 0.96, green: 0.82, blue: 0.48)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                                                .foregroundStyle(Color(red: 0.23, green: 0.14, blue: 0)).padding(8)
                                        }
                                        .overlay(alignment: .bottom) { Text("Im Stapel ansehen").font(.caption.bold()).padding(.bottom, 10) }
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Text(lm.matches.isEmpty ? "Noch keine Matches" : "Deine Matches").font(.title3.bold())
                        Text(lm.matches.isEmpty ? "Like Profile im Stapel – wenn sie dich auch mag, landet ihr hier." : "Antippen, um zu schreiben.")
                            .font(.footnote).foregroundStyle(Farbe.text2)
                        LazyVGrid(columns: spalten, spacing: 10) {
                            ForEach(lm.matches) { m in
                                Button { if let c = m.charId { chat(c) } } label: {
                                    Color.clear.aspectRatio(3 / 4, contentMode: .fit)
                                        .overlay { if let f = m.foto { NetzBild(pfad: f) } }
                                        .overlay(alignment: .bottomLeading) {
                                            Text(m.name + (m.alter.map { ", \($0)" } ?? "")).font(.subheadline.bold())
                                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                                        }
                                        .overlay(alignment: .topLeading) {
                                            if m.neu {
                                                Text("NEU").font(.caption2.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 3)
                                                    .background(Color(red: 0.99, green: 0.15, blue: 0.48), in: Capsule()).padding(8)
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            } else {
                ProgressView().tint(.white).padding(60)
            }
        }
    }
}
