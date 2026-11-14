import Foundation
import WidgetKit

/// Füllt die App-Group für das Home-Bildschirm-Widget: letzte Chats + kleine Avatare.
enum WidgetSchreiber {
    @MainActor
    static func aktualisieren(_ v: Verbindung) async {
        let liste = v.charaktere
            .sorted { ($0.letzte?.zustellen ?? 0) > ($1.letzte?.zustellen ?? 0) }
            .prefix(4)
        let chats = liste.map { c in
            WidgetChat(id: c.id, name: c.name, text: c.letzte?.text ?? "", vonIhr: c.letzte?.rolle == "char",
                       zeit: c.letzte?.zustellen ?? 0, online: c.gerade.verfuegbar)
        }
        Widgetdaten.speichern(Array(chats))
        for c in liste {
            guard let a = c.avatarUrl, let u = Widgetdaten.bildURL(c.id) else { continue }
            // Avatar nur neu holen, wenn er fehlt oder älter als ein Tag ist
            let alter = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                .map { Date().timeIntervalSince($0) } ?? .infinity
            if alter < 86_400 { continue }
            if let d = try? await v.medien(a) { Widgetdaten.bildSpeichern(c.id, d) }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
