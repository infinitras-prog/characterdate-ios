import Foundation
import Observation
import UIKit
import UserNotifications

/// Mitteilungen über Apple: das iPhone meldet sein Push-Token beim PC an (/api/push/geraet). Der PC pusht dann
/// neue Nachrichten und »sie ruft an«, auch wenn die App geschlossen ist – aber nur, solange das iPhone nicht verbunden ist.
@MainActor
@Observable
final class Push {
    static let shared = Push()

    /// Was eine angetippte Mitteilung öffnen soll (HauptAnsicht arbeitet es ab, sobald die Verbindung steht).
    struct Ziel: Equatable { let charId: String; let anruf: Bool; let video: Bool }
    var ziel: Ziel?

    private let tokenSchluessel = "push_token"
    var token: String? { UserDefaults.standard.string(forKey: tokenSchluessel) }

    /// Nach der ersten Verbindung einmal um Erlaubnis fragen, danach bei jedem Start still anmelden.
    func einrichten() async {
        let zentrale = UNUserNotificationCenter.current()
        let stand = await zentrale.notificationSettings()
        if stand.authorizationStatus == .notDetermined {
            _ = try? await zentrale.requestAuthorization(options: [.alert, .sound, .badge])
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func tokenErhalten(_ daten: Data) {
        UserDefaults.standard.set(daten.map { String(format: "%02x", $0) }.joined(), forKey: tokenSchluessel)
        anmeldenWennMoeglich?()
    }

    /// Wird von der App gesetzt: meldet das Token an den aktuell verbundenen PC.
    var anmeldenWennMoeglich: (() -> Void)?

    func anmelden(_ v: Verbindung) async {
        guard let t = token, v.zustand == .verbunden else { return }
        #if DEBUG
        let umgebung = "sandbox"
        #else
        let umgebung = "production"
        #endif
        struct Anfrage: Encodable { let token: String; let umgebung: String }
        struct Antwort: Decodable { let ok: Bool }
        let _: Antwort? = try? await v.anfrage("/api/push/geraet", methode: "POST", body: Anfrage(token: t, umgebung: umgebung))
    }

    /// Angetippte Mitteilung merken.
    func angetippt(_ info: [AnyHashable: Any]) {
        guard let cid = info["char_id"] as? String else { return }
        ziel = Ziel(charId: cid, anruf: (info["art"] as? String) == "anruf", video: info["video"] as? Bool ?? false)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in Push.shared.tokenErhalten(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push-Anmeldung bei Apple fehlgeschlagen: \(error.localizedDescription)")
    }

    /// App ist offen: Anrufe zeigt die App selbst (Klingelbildschirm), Nachrichten als Banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        if (info["art"] as? String) == "anruf" {
            await MainActor.run { Push.shared.angetippt(info) }
            return []
        }
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run { Push.shared.angetippt(info) }
    }
}
