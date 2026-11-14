import SwiftUI
import PhotosUI

struct ChatListe: View {
    @Environment(Verbindung.self) private var v
    @Binding var auswahl: Charakter?

    var sortiert: [Charakter] {
        v.charaktere.filter { ($0.entwurf ?? 0) == 0 }.sorted { ($0.letzte?.zustellen ?? 0) > ($1.letzte?.zustellen ?? 0) }
    }

    var body: some View {
        List {
            ForEach(sortiert) { c in
                Button { auswahl = c } label: {
                    HStack(spacing: 12) {
                        Avatar(c: c, groesse: 52, online: true)
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
    @State private var gross: String?
    @State private var abo: UUID?
    @State private var rekorder = Rekorder()
    @FocusState private var fokus: Bool

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
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: nachrichten.count) { _, _ in withAnimation { leser.scrollTo(nachrichten.last?.id, anchor: .bottom) } }
                .onChange(of: tippt) { _, an in if an { withAnimation { leser.scrollTo("tippt", anchor: .bottom) } } }
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
        }
        .task { await laden() }
        .onAppear {
            abo = v.abonnieren { e in
                guard e.charId == charId else { if e.typ == "verbunden" { Task { await laden() } }; return }
                switch e.typ {
                case "nachricht": if let n = e.nachricht, !nachrichten.contains(where: { $0.id == n.id }) { nachrichten.append(n) }
                case "aktualisiert": if let n = e.nachricht, let i = nachrichten.firstIndex(where: { $0.id == n.id }) { nachrichten[i] = n }
                case "gelesen": gelesenBis = e.roh["bis"] as? Double ?? gelesenBis
                case "tippt": tippt = e.roh["an"] as? Bool ?? false; tipptArt = e.roh["art"] as? String ?? "text"
                case "fehler": fehler = e.roh["text"] as? String; tippt = false
                default: break
                }
            }
        }
        .onDisappear { if let abo { v.abbestellen(abo) } }
        .onChange(of: foto) { _, neu in if let neu { Task { await fotoSenden(neu) } } }
        .fullScreenCover(item: Binding(get: { gross.map { GrossesBild(pfad: $0) } }, set: { gross = $0?.pfad })) { b in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                NetzBild(pfad: b.pfad, modus: .fit)
                Button { gross = nil } label: { Image(systemName: "xmark.circle.fill").font(.largeTitle) }
                    .foregroundStyle(.white.opacity(0.85)).padding()
            }
        }
    }

    // MARK: Zeilen

    @ViewBuilder
    private func zeile(_ m: Nachricht) -> some View {
        if m.art == "anruf" {
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
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func inhalt(_ m: Nachricht) -> some View {
        let ich = m.vonMir
        switch m.art {
        case "bild":
            if !ich && m.m("status")?.text == "entsteht" {
                VStack(spacing: 8) { ProgressView().tint(.white); Text("📷 Foto wird aufgenommen …").font(.footnote) }
                    .frame(width: 220, height: 290).background(Farbe.verlauf.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 18))
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
                .onTapGesture { gross = pfad }
            } else {
                Text("📷 Das Foto ist nicht geworden.").font(.footnote).padding(10).glas(16)
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
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ich ? Color.clear : Farbe.linie, lineWidth: 1))
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

    // MARK: Aktionen

    @MainActor
    private func laden() async {
        do {
            let r: ChatAntwort = try await v.anfrage("/api/charaktere/\(charId)/chat")
            nachrichten = r.nachrichten
            gelesenBis = r.gelesenBis ?? 0
            tippt = c?.tippt ?? false
        } catch { fehler = error.localizedDescription }
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

struct GrossesBild: Identifiable { let pfad: String; var id: String { pfad } }

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
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi * 2 } }
    }
}
