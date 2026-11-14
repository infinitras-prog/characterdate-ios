import Foundation
import UIKit

/// Was App und Widget teilen (App Group): die letzten Chats mit Vorschaubild. Die App schreibt, das Widget liest.
struct WidgetChat: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let text: String
    let vonIhr: Bool
    let zeit: Double
    let online: String?
}

enum Widgetdaten {
    static let gruppe = "group.de.infinitras.characterdate"
    private static let schluessel = "widget_chats"

    static var defaults: UserDefaults { UserDefaults(suiteName: gruppe) ?? .standard }
    static var ordner: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gruppe) }

    static func chats() -> [WidgetChat] {
        guard let d = defaults.data(forKey: schluessel) else { return [] }
        return (try? JSONDecoder().decode([WidgetChat].self, from: d)) ?? []
    }

    static func speichern(_ liste: [WidgetChat]) {
        if let d = try? JSONEncoder().encode(liste) { defaults.set(d, forKey: schluessel) }
    }

    static func bildURL(_ id: String) -> URL? { ordner?.appendingPathComponent("avatar_\(id).jpg") }

    static func bild(_ id: String) -> UIImage? {
        guard let u = bildURL(id), let d = try? Data(contentsOf: u) else { return nil }
        return UIImage(data: d)
    }

    /// Avatar klein rechnen (Widgets dürfen nur wenig Speicher nutzen) und ablegen.
    static func bildSpeichern(_ id: String, _ daten: Data) {
        guard let u = bildURL(id), let img = UIImage(data: daten) else { return }
        let kante: CGFloat = 220
        let f = kante / max(img.size.width, img.size.height, 1)
        let groesse = CGSize(width: max(1, img.size.width * f), height: max(1, img.size.height * f))
        let klein = UIGraphicsImageRenderer(size: groesse).image { _ in img.draw(in: CGRect(origin: .zero, size: groesse)) }
        try? klein.jpegData(compressionQuality: 0.8)?.write(to: u, options: .atomic)
    }
}
