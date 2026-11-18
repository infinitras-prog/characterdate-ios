import AVFoundation
import CallKit
import Foundation
import Observation
import PushKit
import UIKit

/// Was die Oberfläche vom echten Anruf wissen muss. (Der CallKit-Delegat ist ein NSObject und darum getrennt.)
@MainActor
@Observable
final class RufZustand {
    static let shared = RufZustand()
    struct Ruf: Equatable { let uuid: UUID; let charId: String; let name: String; let video: Bool }
    /// Über den System-Anrufbildschirm angenommen → die App zeigt das Gespräch mit diesem Telefon
    var angenommen: Ruf?
    /// Telefon des angenommenen Anrufs – läuft schon, auch bei gesperrtem iPhone
    @ObservationIgnored var telefon: Telefon?
}

/// Echte Anrufe: SIE ruft an → das iPhone klingelt wie bei einem Telefonanruf (Sperrbildschirm, Klingelton, auch wenn
/// die App geschlossen ist). Der PC schickt dafür einen VoIP-Push (PushKit), CallKit zeigt den System-Anrufbildschirm.
/// Wichtig (frühere Erfahrung: CallKit beendete Anrufe sofort): Die Audio-Sitzung aktiviert hier CallKit selbst –
/// das Telefon startet Mikrofon und Stimme erst in »didActivate«, nie vorher.
final class Rufe: NSObject, PKPushRegistryDelegate, CXProviderDelegate {
    static let shared = Rufe()

    private let provider: CXProvider
    private let registry = PKPushRegistry(queue: .main)
    private var offen: [UUID: RufZustand.Ruf] = [:]
    private var angenommen: UUID?
    private let tokenSchluessel = "voip_token"
    /// Für Anfragen (ablehnen, Token melden). Die App setzt sie; im Hintergrund wird bei Bedarf eine eigene aufgebaut.
    var verbindung: Verbindung?

    override init() {
        let k = CXProviderConfiguration()
        k.supportsVideo = true
        k.maximumCallGroups = 1
        k.maximumCallsPerCallGroup = 1
        k.supportedHandleTypes = [.generic]
        k.includesCallsInRecents = false
        provider = CXProvider(configuration: k)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    /// Beim App-Start: für VoIP-Pushes anmelden (das Token kommt über den Delegaten).
    func einrichten() {
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }

    // MARK: Token

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let t = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(t, forKey: tokenSchluessel)
        Task { @MainActor in await self.tokenMelden() }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        UserDefaults.standard.removeObject(forKey: tokenSchluessel)
    }

    @MainActor
    func tokenMelden() async {
        guard let t = UserDefaults.standard.string(forKey: tokenSchluessel), let v = verbindung, v.zustand == .verbunden else { return }
        #if DEBUG
        let umgebung = "sandbox"
        #else
        let umgebung = "production"
        #endif
        struct Anfrage: Encodable { let token: String; let umgebung: String }
        struct Antwort: Decodable { let ok: Bool }
        let _: Antwort? = try? await v.anfrage("/api/push/voip", methode: "POST", body: Anfrage(token: t, umgebung: umgebung))
    }

    @MainActor
    private func verbindungHolen() async -> Verbindung? {
        let v = verbindung ?? Verbindung()
        verbindung = v
        if v.zustand != .verbunden, v.gekoppelt { await v.verbinden() }
        return v.zustand == .verbunden ? v : nil
    }

    // MARK: Klingeln

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        let d = payload.dictionaryPayload
        let cid = d["char_id"] as? String ?? ""
        let name = (d["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "CharacterDate"
        let video = (d["video"] as? Bool) ?? ((d["video"] as? Int) == 1)
        let ende = (d["art"] as? String) == "anruf_ende"
        let uuid = UUID()
        let u = CXCallUpdate()
        u.remoteHandle = CXHandle(type: .generic, value: name)
        u.localizedCallerName = name
        u.hasVideo = video
        u.supportsHolding = false
        u.supportsGrouping = false
        u.supportsUngrouping = false
        u.supportsDTMF = false
        // iOS verlangt: JEDER VoIP-Push meldet einen Anruf – auch das »hört auf zu klingeln« (wird sofort beendet)
        provider.reportNewIncomingCall(with: uuid, update: u) { [weak self] fehler in
            defer { completion() }
            guard let self, fehler == nil else { return }
            if ende {
                self.provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
                for (k, r) in self.offen where r.charId == cid && k != self.angenommen {
                    self.provider.reportCall(with: k, endedAt: nil, reason: .unanswered)
                    self.offen[k] = nil
                }
                return
            }
            self.offen[uuid] = RufZustand.Ruf(uuid: uuid, charId: cid, name: name, video: video)
            // Wie am PC: nach 50 s ohne Abheben ist es ein verpasster Anruf
            DispatchQueue.main.asyncAfter(deadline: .now() + 50) { [weak self] in
                guard let self, self.offen[uuid] != nil, self.angenommen != uuid else { return }
                self.provider.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
                self.offen[uuid] = nil
            }
        }
    }

    // MARK: CallKit

    func providerDidReset(_ provider: CXProvider) {
        offen.removeAll()
        angenommen = nil
        Task { @MainActor in
            RufZustand.shared.telefon?.beenden(grund: "Der Anruf wurde vom iPhone beendet.")
            RufZustand.shared.telefon = nil
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let r = offen[action.callUUID] else { action.fail(); return }
        angenommen = action.callUUID
        // Kategorie vorab setzen – aktivieren tut CallKit selbst (danach didActivate)
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat,
                                                         options: [.allowBluetooth, .allowBluetoothA2DP])
        Task { @MainActor in
            guard let v = await self.verbindungHolen() else {
                self.provider.reportCall(with: r.uuid, endedAt: Date(), reason: .failed)
                return
            }
            var c = v.charaktere.first(where: { $0.id == r.charId })
            if c == nil { await v.neuLaden(); c = v.charaktere.first(where: { $0.id == r.charId }) }
            guard let char = c else {
                self.provider.reportCall(with: r.uuid, endedAt: Date(), reason: .failed)
                return
            }
            let t = Telefon()
            RufZustand.shared.telefon = t
            t.starten(v, char: char, eingehend: true, video: r.video, callKit: true)
            RufZustand.shared.angenommen = r
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let id = action.callUUID
        if id == angenommen {
            angenommen = nil
            Task { @MainActor in RufZustand.shared.telefon?.auflegen() }
        } else if let r = offen[id] {
            Task { @MainActor in
                guard let v = await self.verbindungHolen() else { return }
                struct Ok: Decodable { let ok: Bool }
                let _: Ok? = try? await v.anfrage("/api/charaktere/\(r.charId)/anruf/ablehnen", methode: "POST")
            }
        }
        offen[id] = nil
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let an = action.isMuted
        Task { @MainActor in RufZustand.shared.telefon?.setzeStumm(an) }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in RufZustand.shared.telefon?.callKitAudioBereit() }
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}

    /// Die App (oder der PC) hat aufgelegt → den System-Anruf beenden.
    func beendet() {
        guard let id = angenommen else { return }
        angenommen = nil
        offen[id] = nil
        provider.reportCall(with: id, endedAt: Date(), reason: .remoteEnded)
    }
}
