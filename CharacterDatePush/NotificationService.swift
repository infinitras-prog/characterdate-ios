import Intents
import UIKit
import UserNotifications

/// Macht aus einer Chat-Mitteilung eine »Nachricht von einer Person«: Ihr Profilbild steht links in der Mitteilung
/// (statt des App-Symbols), wie bei iMessage/WhatsApp. Das kleine Bild schickt der PC direkt in der Push-Nachricht mit.
final class NotificationService: UNNotificationServiceExtension {
    private var fertig: ((UNNotificationContent) -> Void)?
    private var inhalt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        fertig = contentHandler
        let c = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        inhalt = c
        let info = request.content.userInfo
        guard let cid = info["char_id"] as? String else { contentHandler(c); return }
        let name = (info["absender"] as? String) ?? c.title
        var bild: INImage?
        if let b64 = info["bild"] as? String, let d = Data(base64Encoded: b64) { bild = INImage(imageData: d) }

        let person = INPerson(personHandle: INPersonHandle(value: cid, type: .unknown), nameComponents: nil,
                              displayName: name, image: bild, contactIdentifier: nil, customIdentifier: cid)
        let absicht = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: c.body,
                                          speakableGroupName: nil, conversationIdentifier: cid, serviceName: nil,
                                          sender: person, attachments: nil)
        if let bild { absicht.setImage(bild, forParameterNamed: \.sender) }
        let ablauf = INInteraction(intent: absicht, response: nil)
        ablauf.direction = .incoming
        ablauf.donate { _ in
            if let neu = try? c.updating(from: absicht) {
                contentHandler(neu)
            } else {
                contentHandler(c)
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let fertig, let inhalt { fertig(inhalt) }
    }
}
