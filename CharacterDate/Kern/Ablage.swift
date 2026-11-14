import Foundation
import CryptoKit

/// Offline lesen: Charaktere, Chats und Fotos bleiben auf dem iPhone, auch wenn der PC aus ist.
/// Liegt im Caches-Ordner der App (iOS darf ihn bei Platzmangel leeren – dann wird einfach neu geladen).
enum Ablage {
    static let ordner: URL = {
        let o = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
        return o
    }()

    static func schreiben<T: Encodable>(_ wert: T, _ name: String) {
        if let d = try? JSONEncoder().encode(wert) { try? d.write(to: ordner.appendingPathComponent(name + ".json"), options: .atomic) }
    }

    static func lesen<T: Decodable>(_ typ: T.Type, _ name: String) -> T? {
        guard let d = try? Data(contentsOf: ordner.appendingPathComponent(name + ".json")) else { return nil }
        return try? JSONDecoder().decode(typ, from: d)
    }

    private static func medienDatei(_ pfad: String) -> URL {
        let h = SHA256.hash(data: Data(pfad.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
        return ordner.appendingPathComponent("m_" + h)
    }
    static func medienLesen(_ pfad: String) -> Data? { try? Data(contentsOf: medienDatei(pfad)) }
    static func medienSchreiben(_ pfad: String, _ d: Data) {
        guard d.count < 40_000_000 else { return }
        try? d.write(to: medienDatei(pfad), options: .atomic)
    }
}
