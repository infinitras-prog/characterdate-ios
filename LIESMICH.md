# CharacterDate AI für iPhone

Native SwiftUI-App (iOS 17+). Die KI läuft auf deinem PC. Das iPhone verbindet sich im Heimnetz oder über
Tailscale und zeigt Chats, Fotos und Sprachnachrichten an.

## Was die App kann (Version 0.6.1)

- Mit dem PC koppeln: QR-Code scannen. Der Schlüssel liegt im iOS-Schlüsselbund und wird nur als Header gesendet.
- Home mit Charakterkarten, Beziehungsring und Stimmung.
- Chats mit Lesebestätigung, Tippanzeige, Fotos (senden und empfangen), Sprachnachrichten (aufnehmen und abspielen)
  und Telefonat-Einträgen.
- Anrufen mit echter Stimme: Telefon-Knopf oben im Chat. Läuft über CallKit (grüne Anzeige, Sperrbildschirm,
  Bluetooth), mit Echo-Unterdrückung, Freizeichen, Untertiteln, Stumm und Lautsprecher. Dazwischenreden unterbricht sie.
- Animierter Startbildschirm mit Glas-Herz (Herzschlag, Lichtstrahlen, Partikelring, Blitz + Name), lebendiger Hintergrund, Herzschlag-Logo, federnde Karten und Nachrichten, Haptik.
- Charakter aus Beschreibung erstellen, optional mit Referenzbild.
- Galerie mit Filtern.
- Face ID als Sperre, Entkoppeln.

Noch nicht dabei (nächste Schritte): Sie ruft dich an (braucht Push), Mitteilungen per Push, Widgets.

## Bauen ohne Mac (GitHub Actions)

Gleicher Weg wie bei NitraX-iOS:

1. Neues privates GitHub-Repository anlegen, z. B. `characterdate-ios`.
2. Den **Inhalt dieses Ordners** (`CharacterDate\ios`) mit GitHub Desktop hochladen, auf den Zweig `main`.
3. Der Job **Prüfen** startet automatisch und baut die App ohne Signatur. Erst er zeigt, ob der Code fehlerfrei
   kompiliert (auf Windows gibt es keinen Swift-Compiler).
4. Unter Settings → Secrets and variables → Actions dieselben vier Secrets wie bei NitraX eintragen:
   `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`.
5. Actions → iOS → Run workflow → *testflight* anhaken. Die App-ID `de.infinitras.characterdate` legt der Lauf selbst an.
6. In App Store Connect die App einmal anlegen (Name „CharacterDate AI“, Bundle-ID wie oben). Danach erscheint jeder
   Build in TestFlight.

Die Version steht in der Datei `VERSION` und wird bei jedem Update hochgezählt.

## Am PC vorbereiten

CharacterDate → Einstellungen → **iPhone** → Fernzugriff einschalten → CharacterDate neu starten (Windows fragt
einmal nach der Firewall für „Privates Netzwerk“) → **QR-Code anzeigen**.
Für unterwegs: Tailscale auf PC und iPhone. Die 100.x-Adresse steckt automatisch im QR-Code.
