import Foundation

/// Beliebiger JSON-Wert (für die frei aufgebauten »meta«-Felder des Kerns).
enum JSONWert: Codable, Hashable {
    case text(String), zahl(Double), wahr(Bool), objekt([String: JSONWert]), liste([JSONWert]), nichts

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .nichts }
        else if let b = try? c.decode(Bool.self) { self = .wahr(b) }
        else if let d = try? c.decode(Double.self) { self = .zahl(d) }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else if let o = try? c.decode([String: JSONWert].self) { self = .objekt(o) }
        else if let l = try? c.decode([JSONWert].self) { self = .liste(l) }
        else { self = .nichts }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .zahl(let d): try c.encode(d)
        case .wahr(let b): try c.encode(b)
        case .objekt(let o): try c.encode(o)
        case .liste(let l): try c.encode(l)
        case .nichts: try c.encodeNil()
        }
    }

    var text: String? { if case .text(let s) = self { return s }; return nil }
    var zahl: Double? { if case .zahl(let d) = self { return d }; return nil }
    var wahr: Bool? { if case .wahr(let b) = self { return b }; return nil }
}

struct ErstesMal: Codable, Hashable { let text: String; let wann: Double }

struct Beziehung: Codable, Hashable {
    var level: Int
    var xp: Double
    var levelName: String?
    var fortschritt: Double?
    var stimmung: String
    var stimmungGrund: String?
    var ersteMale: [ErstesMal]?
}

struct Gerade: Codable, Hashable { let was: String; let ort: String; let verfuegbar: String }

struct Letzte: Codable, Hashable { let text: String; let rolle: String; let zustellen: Double }

struct Leben: Codable, Hashable {
    var beruf: String?
    var interessen: [String]?
    var hobbys: [String]?
}

struct StimmeInfo: Codable, Hashable {
    var refWav: String?
    var refText: String?
    var original: String?
    var originalDauer: Double?
    var von: Double?
    var bis: Double?
}

struct DNA: Codable, Hashable {
    var name: String
    var alter: Int
    var geschlecht: String?
    var kurzbeschreibung: String?
    var leben: Leben?
    var stimme: StimmeInfo?
    var referenzbilder: [String]?
    var swipe: Bool?
}

struct Charakter: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var avatarUrl: String?
    var dna: DNA
    var beziehung: Beziehung
    var gerade: Gerade
    var letzte: Letzte?
    var tippt: Bool?
    var entwurf: Int?

    var hatStimme: Bool { (dna.stimme?.refWav ?? "").isEmpty == false }
    var tags: [String] { Array(((dna.leben?.interessen ?? []) + (dna.leben?.hobbys ?? [])).prefix(4)) }
}

struct Nachricht: Codable, Identifiable, Hashable {
    let id: String
    let rolle: String
    let art: String
    var text: String
    let erstellt: Double
    let zustellen: Double
    var gelesen: Double?
    var meta: [String: JSONWert]?

    var vonMir: Bool { rolle == "nutzer" }
    func m(_ k: String) -> JSONWert? { meta?[k] }
}

struct ChatAntwort: Codable { let nachrichten: [Nachricht]; let gelesenBis: Double? }

struct Bild: Codable, Identifiable, Hashable {
    let id: String
    let charId: String
    let pfad: String
    let url: String
    let art: String
    let beschreibung: String
    let erstellt: Double
    var meta: [String: JSONWert]?

    var poster: String? { meta?["poster"]?.text.map { $0.hasPrefix("/api/") ? $0 : "/api/medien/\($0)" } }
}

struct KopplungsCode: Codable { let app: String; let code: String; let adressen: [String]; let name: String? }
struct KopplungsAntwort: Codable { let geraetId: String; let schluessel: String; let version: String? }
