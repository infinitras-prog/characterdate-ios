import SwiftUI

/// Vollbild-Telefonat: verschwommenes Porträt, pulsierender Ring (leuchtet, wenn sie spricht), Untertitel.
struct AnrufAnsicht: View {
    @Environment(Verbindung.self) private var v
    @Environment(\.dismiss) private var schliessen
    let c: Charakter
    var video = false
    var eingehend = false
    @State private var telefon = Telefon()
    @State private var puls = false
    @State private var portraet: UIImage?
    @State private var bildKennung = "avatar"
    @State private var augen = Augen()
    @State private var clips = ClipSpieler()
    @State private var tippen = false
    @State private var getippt = ""
    @FocusState private var tippFokus: Bool
    @State private var ort: String?
    @State private var abo: UUID?

    var body: some View {
        ZStack {
            Farbe.grund.ignoresSafeArea()
            if video, clips.bereit {
                ClipAnsicht(spieler: clips.spieler).ignoresSafeArea().transition(.opacity)
                LinearGradient(colors: [.black.opacity(0.5), .clear, .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            } else if video, let portraet {
                // Videoanruf: ihr Profilbild lebt (Mund nach Stimme, Blinzeln, Kopfbewegung)
                LebendigesPortraet(bild: portraet, pegel: { telefon.pegelSie }, aktiv: telefon.zustand == .aktiv)
                    .id(bildKennung)                       // neues Szenenbild → Animation neu aufbauen
                    .transition(.opacity)
                    .ignoresSafeArea()
                if let ort {
                    VStack { HStack { Label(ort, systemImage: "mappin.and.ellipse").font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule()); Spacer() }; Spacer() }
                        .padding(.top, 60).padding(.leading, 16)
                }
                LinearGradient(colors: [.black.opacity(0.5), .clear, .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            } else if let a = c.avatarUrl {
                NetzBild(pfad: a).ignoresSafeArea().blur(radius: 40).opacity(0.55).scaleEffect(1.2)
            }
            LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if augen.an {
                VStack {
                    HStack {
                        Spacer()
                        ZStack(alignment: .bottomLeading) {
                            KameraVorschau(sitzung: augen.sitzung)
                                .frame(width: 110, height: 160).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Label("sieht dich", systemImage: "eye.fill").font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 3).background(Farbe.mint.opacity(0.9), in: Capsule())
                                .foregroundStyle(.black).padding(6)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1))
                        .shadow(radius: 10)
                        .onTapGesture { augen.wechseln() }
                        .accessibilityLabel("Kamera wechseln")
                    }
                    Spacer()
                }
                .padding(.top, 56).padding(.trailing, 16)
                .transition(.scale.combined(with: .opacity))
            }

            VStack(spacing: 18) {
                Spacer(minLength: video ? 10 : 40)
                if !video { ring }
                Text(c.name).font(.system(size: 32, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(statusText).font(.headline.monospacedDigit()).foregroundStyle(Farbe.text2)
                }
                if let g = telefon.grund {
                    VStack(spacing: 14) {
                        Text(g).font(.callout).foregroundStyle(.white).multilineTextAlignment(.center)
                        Button("Schließen") { schliessen() }.buttonStyle(HauptKnopf())
                    }
                    .padding(18).glas().padding(.horizontal, 24)
                } else if let i = telefon.info {
                    Text(i).font(.footnote).foregroundStyle(Farbe.text3).multilineTextAlignment(.center).padding(.horizontal, 30)
                }
                Spacer()
                untertitel
                if !video { Spacer() }
                if tippen && telefon.zustand == .aktiv { tippZeile }
                knoepfe.padding(.bottom, 30)
            }
            .foregroundStyle(.white)
        }
        .statusBarHidden(telefon.zustand == .aktiv)
        .task {
            guard video else { return }
            // Echte Bewegungen: Clips zur Szene (falls schon gedreht) – sonst lebendes Standbild
            struct ClipListe: Decodable { let clips: [String: String] }
            if let l: ClipListe = try? await v.anfrage("/api/charaktere/\(c.id)/anrufclips?format=hoch"), l.clips["ruhe"] != nil {
                clips.sieRedet = { [t = telefon] in t.pegelSie > 0.05 }
                clips.duRedest = { [t = telefon] in t.pegelDu > 0.05 }
                await clips.laden(v, clips: l.clips)
            }
            // Szenenbild 9:16: dort, wo sie laut Chat gerade ist – sonst erst das Profilbild
            struct Szene: Decodable { let url: String?; let ort: String? }
            if let s: Szene = try? await v.anfrage("/api/charaktere/\(c.id)/videoszene?format=hoch&nur_lesen=1", methode: "POST"),
               let u = s.url, let d = try? await v.medien(u), let b = UIImage(data: d) {
                portraet = b; bildKennung = u; ort = s.ort
            } else if let a = c.avatarUrl, let d = try? await v.medien(a) { portraet = UIImage(data: d) }
            abo = v.abonnieren { e in
                guard e.typ == "videoszene", e.charId == c.id, (e.roh["format"] as? String) == "hoch",
                      let u = e.roh["url"] as? String else { return }
                Task { @MainActor in
                    if let d = try? await v.medien(u), let b = UIImage(data: d) {
                        withAnimation(.easeInOut(duration: 0.8)) { portraet = b; bildKennung = u; ort = e.roh["ort"] as? String }
                    }
                }
            }
        }
        .onDisappear { if let abo { v.abbestellen(abo) }; augen.ausschalten(); clips.stoppen() }
        .onChange(of: telefon.sieText) { _, t in
            if t.range(of: #"ha(ha)+|hihi|lach"#, options: [.regularExpression, .caseInsensitive]) != nil {
                clips.lachenBis = Date().addingTimeInterval(2.5)
            }
        }
        .onAppear {
            telefon.starten(v, char: c, eingehend: eingehend)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {   // erst nach dem Layout, sonst wandert die Ansicht mit
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { puls = true }
            }
        }
        .onDisappear {
            if telefon.zustand != .beendet {
                telefon.melden("Anrufbildschirm verschwand, während der Anruf noch lief (Zustand \(telefon.zustand))")
                telefon.beenden()
            }
        }
        .onChange(of: telefon.zustand) { _, z in
            if z == .beendet {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                if telefon.grund == nil {        // normal aufgelegt: kurz »Anruf beendet«, dann zu
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { schliessen() }
                }                                // mit Grund (Problem): bleibt stehen, bis du »Schließen« tippst
            } else if z == .aktiv {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    private var statusText: String {
        switch telefon.zustand {
        case .waehlt: return "Wählt …"
        case .klingelt: return "Klingelt …"
        case .beendet: return "Anruf beendet"
        case .aktiv:
            let s = Int(Date().timeIntervalSince(telefon.start ?? Date()))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }

    private var ring: some View {
        let sie = CGFloat(telefon.pegelSie)
        let klingelt = telefon.zustand != .aktiv && telefon.zustand != .beendet
        return ZStack {
            ForEach(0..<3) { i in
                Circle().stroke(Farbe.verlauf, lineWidth: 2)
                    .frame(width: 190, height: 190)
                    .scaleEffect(klingelt ? (puls ? 1.0 + CGFloat(i + 1) * 0.16 : 1.0) : 1.0 + sie * CGFloat(i + 1) * 0.12)
                    .opacity(klingelt ? (puls ? 0 : 0.6) : Double(0.15 + sie * 0.6) / Double(i + 1))
            }
            Circle().fill(Farbe.verlauf).frame(width: 196, height: 196).blur(radius: 18).opacity(0.25 + Double(sie) * 0.6)
            Avatar(c: c, groesse: 180)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .scaleEffect(1 + sie * 0.04)
        }
        .animation(.easeOut(duration: 0.12), value: telefon.pegelSie)
        .frame(height: 260)
    }

    private var untertitel: some View {
        VStack(spacing: 10) {
            if !telefon.sieText.isEmpty {
                Text(telefon.sieText).font(.title3.weight(.medium)).multilineTextAlignment(.center)
                    .transition(.opacity).id("sie" + telefon.sieText)
            }
            if !telefon.duText.isEmpty {
                Text("Du: \(telefon.duText)").font(.subheadline).foregroundStyle(Farbe.text2).multilineTextAlignment(.center)
                    .transition(.opacity).id("du" + telefon.duText)
            }
        }
        .padding(.horizontal, 28)
        .animation(.easeOut(duration: 0.3), value: telefon.sieText + telefon.duText)
        .frame(minHeight: 110)
    }

    private var tippZeile: some View {
        HStack(spacing: 8) {
            TextField("Nachricht – sie antwortet mit Stimme", text: $getippt)
                .focused($tippFokus).submitLabel(.send)
                .onSubmit { tippAbschicken() }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            Button { tippAbschicken() } label: {
                Image(systemName: "paperplane.fill").foregroundStyle(.white).frame(width: 40, height: 40)
                    .background(Farbe.verlauf, in: Circle())
            }
            .disabled(getippt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
    }

    private func tippAbschicken() {
        let t = getippt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        telefon.textSenden(t); getippt = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var knoepfe: some View {
        HStack(spacing: 18) {
            rund("keyboard", text: "Schreiben", an: tippen) {
                tippen.toggle(); tippFokus = tippen
            }
            rund(telefon.stumm ? "mic.slash.fill" : "mic.fill", text: telefon.stumm ? "Stumm" : "Mikro", an: telefon.stumm) {
                telefon.stummSchalten()
            }
            rund(augen.an ? "eye.fill" : "eye.slash", text: augen.an ? (augen.hinten ? "Rückkamera" : "Frontkamera") : "Ihre Augen", an: augen.an) {
                if augen.an {
                    augen.ausschalten(); telefon.kameraMelden(false)
                } else {
                    Task {
                        augen.bild = { [t = telefon] url in t.blickSenden(url) }
                        if await augen.einschalten() { telefon.kameraMelden(true) }
                    }
                }
            }
            Button { telefon.auflegen() } label: {
                Image(systemName: "phone.down.fill").font(.system(size: 30, weight: .semibold))
                    .frame(width: 78, height: 78).background(Color.red, in: Circle())
                    .shadow(color: .red.opacity(0.5), radius: 16)
            }
            .accessibilityLabel("Auflegen")
            .disabled(telefon.zustand == .beendet)
            rund(telefon.lautsprecher ? "speaker.wave.3.fill" : "speaker.fill", text: "Lautsprecher", an: telefon.lautsprecher) {
                telefon.lautsprecherSchalten()
            }
        }
    }

    private func rund(_ symbol: String, text: String, an: Bool, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .background(an ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.14)), in: Circle())
                    .foregroundStyle(an ? Color.black : Color.white)
                Text(text).font(.caption2).foregroundStyle(Farbe.text2)
            }
        }
        .disabled(telefon.zustand == .beendet)
    }
}
