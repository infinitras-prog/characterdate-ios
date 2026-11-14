import SwiftUI
import AVFoundation

/// Erster Start: mit dem PC koppeln (QR-Code aus CharacterDate → Einstellungen → iPhone).
struct KopplungAnsicht: View {
    @Environment(Verbindung.self) private var v
    @State private var scannen = false
    @State private var arbeitet = false
    @State private var fehler: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Herz(groesse: 70)
            VStack(spacing: 6) {
                Text("Character").font(.system(size: 34, weight: .semibold, design: .rounded))
                + Text("Date").font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(Farbe.rose)
                + Text(" AI").font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(Farbe.violett)
                Text("Deine KI-Charaktere · Chatten · Daten").font(.subheadline).foregroundStyle(Farbe.text2)
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("Am PC CharacterDate öffnen", systemImage: "desktopcomputer")
                Label("Einstellungen → iPhone → Fernzugriff an", systemImage: "wifi")
                Label("„QR-Code anzeigen“ und hier scannen", systemImage: "qrcode.viewfinder")
            }
            .font(.callout).foregroundStyle(Farbe.text2)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).glas()
            if let fehler { Text(fehler).font(.footnote).foregroundStyle(Farbe.rose).multilineTextAlignment(.center) }
            Spacer()
            Button { scannen = true } label: {
                HStack { Image(systemName: arbeitet ? "hourglass" : "qrcode.viewfinder"); Text(arbeitet ? "Verbinde …" : "Mit PC koppeln") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HauptKnopf()).disabled(arbeitet)
        }
        .padding(24)
        .sheet(isPresented: $scannen) {
            QRScanner { text in
                scannen = false
                Task { await koppeln(text) }
            }
            .ignoresSafeArea()
        }
    }

    @MainActor
    private func koppeln(_ text: String) async {
        fehler = nil
        guard let d = text.data(using: .utf8), let code = try? JSONDecoder().decode(KopplungsCode.self, from: d) else {
            fehler = "Das ist kein CharacterDate-Code."; return
        }
        arbeitet = true
        defer { arbeitet = false }
        do { try await v.koppeln(mit: code) } catch { fehler = error.localizedDescription }
    }
}

/// QR-Scanner mit der Rückkamera.
struct QRScanner: UIViewControllerRepresentable {
    let gefunden: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.gefunden = gefunden
        return vc
    }
    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var gefunden: ((String) -> Void)?
        private let sitzung = AVCaptureSession()
        private var fertig = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let kamera = AVCaptureDevice.default(for: .video),
                  let eingang = try? AVCaptureDeviceInput(device: kamera), sitzung.canAddInput(eingang) else {
                let l = UILabel(); l.text = "Keine Kamera verfügbar"; l.textColor = .white
                l.frame = view.bounds; l.textAlignment = .center; view.addSubview(l); return
            }
            sitzung.addInput(eingang)
            let ausgang = AVCaptureMetadataOutput()
            guard sitzung.canAddOutput(ausgang) else { return }
            sitzung.addOutput(ausgang)
            ausgang.setMetadataObjectsDelegate(self, queue: .main)
            ausgang.metadataObjectTypes = [.qr]
            let vorschau = AVCaptureVideoPreviewLayer(session: sitzung)
            vorschau.videoGravity = .resizeAspectFill
            vorschau.frame = view.layer.bounds
            view.layer.addSublayer(vorschau)
            let rahmen = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
            rahmen.layer.borderColor = UIColor(red: 0.94, green: 0.39, blue: 0.71, alpha: 1).cgColor
            rahmen.layer.borderWidth = 3; rahmen.layer.cornerRadius = 24
            rahmen.center = view.center
            rahmen.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
            view.addSubview(rahmen)
            DispatchQueue.global(qos: .userInitiated).async { [sitzung] in sitzung.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach { $0.frame = view.layer.bounds }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            DispatchQueue.global().async { [sitzung] in sitzung.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !fertig, let o = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let t = o.stringValue else { return }
            fertig = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            gefunden?(t)
        }
    }
}
