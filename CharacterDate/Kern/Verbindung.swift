import Foundation
import Observation
import Security
import UIKit

/// Verbindung zum CharacterDate-Kern auf dem PC: Kopplung, Anfragen, Ereignisse (WebSocket).
/// Der Geräteschlüssel liegt im iOS-Schlüsselbund und geht nur als Header mit – nie in einer URL.
@Observable
final class Verbindung {
    enum Zustand: Equatable { case nichtGekoppelt, verbindet, verbunden, offline(String) }

    var zustand: Zustand = .nichtGekoppelt
    var pcName: String = UserDefaults.standard.string(forKey: "pc_name") ?? "PC"
    var adressen: [String] = UserDefaults.standard.stringArray(forKey: "pc_adressen") ?? []
    var basis: URL?
    var charaktere: [Charakter] = []
    /// Wo du zuletzt etwas eingegeben hast (»pc« oder »iphone«): nur dort spricht sie / wird vorgelesen / klingt es.
    var aktivesGeraet: String = "pc"
    var iphoneAktiv: Bool { aktivesGeraet == "iphone" }

    private var schluessel: String? = Schluesselbund.lesen("geraet")
    private var socket: URLSessionWebSocketTask?
    private var hoerer: [UUID: (Ereignis) -> Void] = [:]
    private let sitzung: URLSession = {
        let k = URLSessionConfiguration.default
        k.timeoutIntervalForRequest = 30
        k.waitsForConnectivity = false
        return URLSession(configuration: k)
    }()

    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    var gekoppelt: Bool { schluessel != nil && !adressen.isEmpty }

    // MARK: Kopplung

    @MainActor
    func koppeln(mit code: KopplungsCode) async throws {
        guard code.app == "characterdate" else { throw Fehler.text("Das ist kein CharacterDate-Code.") }
        var letzter: Error = Fehler.text("Der PC ist nicht erreichbar. Sind iPhone und PC im selben WLAN (oder Tailscale an)?")
        for a in code.adressen {
            guard let url = URL(string: a + "/api/kopplung/abschliessen") else { continue }
            var r = URLRequest(url: url, timeoutInterval: 6)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONEncoder().encode(["code": code.code, "name": UIDevice.current.name])
            do {
                let (daten, antwort) = try await sitzung.data(for: r)
                guard let h = antwort as? HTTPURLResponse else { continue }
                if h.statusCode != 200 { letzter = Fehler.vomServer(daten, h.statusCode); continue }
                let k = try decoder.decode(KopplungsAntwort.self, from: daten)
                Schluesselbund.schreiben("geraet", k.schluessel)
                schluessel = k.schluessel
                adressen = code.adressen
                pcName = code.name ?? "PC"
                UserDefaults.standard.set(adressen, forKey: "pc_adressen")
                UserDefaults.standard.set(pcName, forKey: "pc_name")
                await verbinden()
                return
            } catch { letzter = error }
        }
        throw letzter
    }

    func entkoppeln() {
        socket?.cancel()
        Schluesselbund.loeschen("geraet")
        schluessel = nil
        adressen = []
        basis = nil
        charaktere = []
        UserDefaults.standard.removeObject(forKey: "pc_adressen")
        zustand = .nichtGekoppelt
    }

    // MARK: Verbinden

    /// Erste erreichbare Adresse wählen (Heimnetz zuerst, dann Tailscale), Daten laden, Ereignisse abonnieren.
    @MainActor
    func verbinden() async {
        guard gekoppelt else { zustand = .nichtGekoppelt; return }
        // Während eines Anrufs nie neu verbinden: das würde Adresse und Liste kurz leeren und den Anruf beenden
        if Telefon.laeuft { return }
        let alteBasis = basis
        zustand = .verbindet
        let liste = adressen
        let s = sitzung
        let gefunden: URL? = await withTaskGroup(of: URL?.self, returning: URL?.self) { gruppe in
            for a in liste {
                gruppe.addTask {
                    guard let u = URL(string: a), let p = URL(string: a + "/api/kopplung/ping") else { return nil }
                    let r = URLRequest(url: p, timeoutInterval: 3)
                    if let ergebnis = try? await s.data(for: r),
                       (ergebnis.1 as? HTTPURLResponse)?.statusCode == 200 { return u }
                    return nil
                }
            }
            for await u in gruppe {
                if let u { gruppe.cancelAll(); return u }
            }
            return nil
        }
        basis = gefunden ?? alteBasis
        guard gefunden != nil else {
            zustand = .offline("PC nicht erreichbar – du siehst die zuletzt geladenen Chats. Läuft CharacterDate am PC?")
            if charaktere.isEmpty, let alt = Ablage.lesen([Charakter].self, "charaktere") { charaktere = alt }
            return
        }
        do {
            charaktere = try await anfrage("/api/charaktere")
            Ablage.schreiben(charaktere, "charaktere")
            zustand = .verbunden
            ereignisseStarten()
            struct AG: Decodable { let geraet: String }
            if let g: AG = try? await anfrage("/api/geraet/aktiv") { aktivesGeraet = g.geraet }
        } catch {
            if case .status(401, _)? = error as? Fehler { entkoppeln(); return }
            zustand = .offline(error.localizedDescription)
        }
    }

    @MainActor
    func neuLaden() async {
        if let c: [Charakter] = try? await anfrage("/api/charaktere") { charaktere = c; Ablage.schreiben(c, "charaktere") }
    }

    // MARK: Anfragen

    func anfrage<T: Decodable>(_ pfad: String, methode: String = "GET", body: Encodable? = nil, zeit: TimeInterval = 60) async throws -> T {
        let daten = try await roh(pfad, methode: methode, body: body, zeit: zeit)
        return try decoder.decode(T.self, from: daten)
    }

    /// Fertiges JSON unverändert senden (z. B. eine DNA, deren snake_case-Schlüssel erhalten bleiben müssen).
    func anfrageRoh<T: Decodable>(_ pfad: String, json: Data, zeit: TimeInterval = 60) async throws -> T {
        let daten = try await roh(pfad, methode: "POST", rohJSON: json, zeit: zeit)
        return try decoder.decode(T.self, from: daten)
    }

    @discardableResult
    func roh(_ pfad: String, methode: String = "GET", body: Encodable? = nil, rohJSON: Data? = nil,
             zeit: TimeInterval = 60) async throws -> Data {
        guard let b = basis, let url = URL(string: pfad, relativeTo: b) else { throw Fehler.text("Nicht verbunden.") }
        var r = URLRequest(url: url, timeoutInterval: zeit)
        r.httpMethod = methode
        if let k = schluessel { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        } else if let rohJSON {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = rohJSON
        }
        let (daten, antwort) = try await sitzung.data(for: r)
        let code = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Fehler.vomServer(daten, code) }
        return daten
    }

    /// Datei hochladen (multipart/form-data).
    func hochladen<T: Decodable>(_ pfad: String, datei: Data, name: String, typ: String, felder: [String: String] = [:]) async throws -> T {
        guard let b = basis, let url = URL(string: pfad, relativeTo: b) else { throw Fehler.text("Nicht verbunden.") }
        let grenze = "cd-\(UUID().uuidString)"
        var body = Data()
        for (k, v) in felder {
            body.append("--\(grenze)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
        }
        body.append("--\(grenze)\r\nContent-Disposition: form-data; name=\"datei\"; filename=\"\(name)\"\r\nContent-Type: \(typ)\r\n\r\n".data(using: .utf8)!)
        body.append(datei)
        body.append("\r\n--\(grenze)--\r\n".data(using: .utf8)!)
        var r = URLRequest(url: url, timeoutInterval: 300)
        r.httpMethod = "POST"
        r.setValue("multipart/form-data; boundary=\(grenze)", forHTTPHeaderField: "Content-Type")
        if let k = schluessel { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        let (daten, antwort) = try await sitzung.upload(for: r, from: body)
        let code = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Fehler.vomServer(daten, code) }
        return try decoder.decode(T.self, from: daten)
    }

    /// Mehrere Dateien in einem Feld hochladen (multipart/form-data), z. B. Fotos eines Lumigram-Beitrags.
    func hochladenMehrere<T: Decodable>(_ pfad: String, dateien: [Data], feld: String, typ: String, felder: [String: String] = [:]) async throws -> T {
        guard let b = basis, let url = URL(string: pfad, relativeTo: b) else { throw Fehler.text("Nicht verbunden.") }
        let grenze = "cd-\(UUID().uuidString)"
        var body = Data()
        for (k, v) in felder {
            body.append("--\(grenze)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
        }
        let endung = typ == "image/png" ? "png" : "jpg"
        for (i, d) in dateien.enumerated() {
            body.append("--\(grenze)\r\nContent-Disposition: form-data; name=\"\(feld)\"; filename=\"bild\(i).\(endung)\"\r\nContent-Type: \(typ)\r\n\r\n".data(using: .utf8)!)
            body.append(d)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(grenze)--\r\n".data(using: .utf8)!)
        var r = URLRequest(url: url, timeoutInterval: 300)
        r.httpMethod = "POST"
        r.setValue("multipart/form-data; boundary=\(grenze)", forHTTPHeaderField: "Content-Type")
        if let k = schluessel { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        let (daten, antwort) = try await sitzung.upload(for: r, from: body)
        let code = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Fehler.vomServer(daten, code) }
        return try decoder.decode(T.self, from: daten)
    }

    /// Medien (Bilder, Ton) mit Schlüssel im Header laden.
    func medien(_ rel: String) async throws -> Data {
        let pfad = rel.hasPrefix("/api/") ? rel : "/api/medien/" + rel
        if let d = MedienCache.shared.object(forKey: pfad as NSString) { return d as Data }
        do {
            let d = try await roh(pfad, zeit: 60)
            MedienCache.shared.setObject(d as NSData, forKey: pfad as NSString, cost: d.count)
            Ablage.medienSchreiben(pfad, d)
            return d
        } catch {
            if let d = Ablage.medienLesen(pfad) { return d }      // offline: aus der Ablage
            throw error
        }
    }

    // MARK: Ereignisse

    struct Ereignis {
        let typ: String
        let charId: String?
        let roh: [String: Any]
        var nachricht: Nachricht? {
            guard let n = roh["nachricht"], let d = try? JSONSerialization.data(withJSONObject: n) else { return nil }
            let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
            return try? dec.decode(Nachricht.self, from: d)
        }
    }

    func abonnieren(_ f: @escaping (Ereignis) -> Void) -> UUID {
        let id = UUID(); hoerer[id] = f; return id
    }
    func abbestellen(_ id: UUID) { hoerer[id] = nil }

    /// WebSocket für ein Telefonat (Schlüssel im Header).
    func anrufSocket(_ charId: String, eingehend: Bool = false) -> URLSessionWebSocketTask? {
        guard let b = basis, var teile = URLComponents(url: b, resolvingAgainstBaseURL: false) else { return nil }
        teile.scheme = teile.scheme == "https" ? "wss" : "ws"
        teile.path = "/ws/anruf/\(charId)"
        if eingehend { teile.queryItems = [URLQueryItem(name: "eingehend", value: "1")] }
        guard let url = teile.url else { return nil }
        var r = URLRequest(url: url)
        if let k = schluessel { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        let s = sitzung.webSocketTask(with: r)
        s.maximumMessageSize = 4 * 1024 * 1024
        return s
    }

    /// Bildstrom des lebendigen Gesichts im Videoanruf.
    func gesichtSocket(_ charId: String, bild: String?) -> URLSessionWebSocketTask? {
        guard let b = basis, var teile = URLComponents(url: b, resolvingAgainstBaseURL: false) else { return nil }
        teile.scheme = teile.scheme == "https" ? "wss" : "ws"
        teile.path = "/ws/gesicht/\(charId)"
        if let bild, !bild.isEmpty { teile.queryItems = [URLQueryItem(name: "bild", value: bild)] }
        guard let url = teile.url else { return nil }
        var r = URLRequest(url: url)
        if let k = schluessel { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        let s = sitzung.webSocketTask(with: r)
        s.maximumMessageSize = 8 * 1024 * 1024
        return s
    }

    private func ereignisseStarten() {
        socket?.cancel()
        guard let b = basis, var teile = URLComponents(url: b, resolvingAgainstBaseURL: false) else { return }
        teile.scheme = teile.scheme == "https" ? "wss" : "ws"
        teile.path = "/ws"
        guard let url = teile.url else { return }
        var r = URLRequest(url: url)
        if let k = schluessel { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        let s = sitzung.webSocketTask(with: r)
        socket = s
        s.resume()
        empfangen(s)
        Task { [weak self] in
            while let self, self.socket === s {
                try? await Task.sleep(for: .seconds(25))
                s.send(.string("ping")) { _ in }
            }
        }
    }

    private func empfangen(_ s: URLSessionWebSocketTask) {
        s.receive { [weak self] ergebnis in
            guard let self else { return }
            switch ergebnis {
            case .success(.string(let t)):
                if let d = t.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    let e = Ereignis(typ: j["typ"] as? String ?? "", charId: j["char_id"] as? String, roh: j)
                    Task { @MainActor in self.verteilen(e) }
                }
                self.empfangen(s)
            case .success:
                self.empfangen(s)
            case .failure:
                guard self.socket === s else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if self.socket === s, self.zustand == .verbunden { self.ereignisseStarten() }
                }
            }
        }
    }

    @MainActor
    private func verteilen(_ e: Ereignis) {
        if e.typ == "aktives_geraet", let g = e.roh["geraet"] as? String { aktivesGeraet = g }
        if ["nachricht", "beziehung", "tippt"].contains(e.typ), let cid = e.charId, let i = charaktere.firstIndex(where: { $0.id == cid }) {
            if e.typ == "tippt" { charaktere[i].tippt = e.roh["an"] as? Bool }
            if e.typ == "nachricht", let n = e.nachricht {
                charaktere[i].letzte = Letzte(text: n.text, rolle: n.rolle, zustellen: n.zustellen)
            }
            if e.typ == "beziehung" { Task { await neuLaden() } }
        }
        hoerer.values.forEach { $0(e) }
    }

    // MARK: Fehler

    enum Fehler: LocalizedError {
        case text(String)
        case status(Int, String)
        static func vomServer(_ d: Data, _ code: Int) -> Fehler {
            if let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let t = j["detail"] as? String {
                return .status(code, t)
            }
            return .status(code, "Fehler \(code)")
        }
        var errorDescription: String? {
            switch self {
            case .text(let t): return t
            case .status(_, let t): return t
            }
        }
    }
}

/// Encodable in einer Box, damit `anfrage(body:)` beliebige Werte nehmen kann.
struct AnyEncodable: Encodable {
    let wert: Encodable
    init(_ w: Encodable) { wert = w }
    func encode(to encoder: Encoder) throws { try wert.encode(to: encoder) }
}

final class MedienCache {
    static let shared: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.totalCostLimit = 150 * 1024 * 1024
        return c
    }()
}

enum Schluesselbund {
    private static let dienst = "de.infinitras.characterdate"
    static func schreiben(_ konto: String, _ wert: String) {
        loeschen(konto)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst,
                                kSecAttrAccount as String: konto, kSecValueData as String: Data(wert.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func lesen(_ konto: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst,
                                kSecAttrAccount as String: konto, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var erg: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &erg) == errSecSuccess, let d = erg as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func loeschen(_ konto: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst,
                                kSecAttrAccount as String: konto]
        SecItemDelete(q as CFDictionary)
    }
}
