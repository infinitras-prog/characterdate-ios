import AVFoundation
import SwiftUI
import UIKit

/// Ihre Augen im Anruf: Front- oder Rückkamera des iPhones. Alle 2,5 s geht ein kleines Standbild (JPEG, 640 px) an den
/// PC-Kern – sie sieht es bei jeder Antwort und kommentiert in Gesprächspausen von sich aus, was sich zeigt.
@Observable
final class Augen: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var an = false
    var hinten = false
    let sitzung = AVCaptureSession()
    @ObservationIgnored var bild: ((String) -> Void)?
    @ObservationIgnored private let warteschlange = DispatchQueue(label: "augen")
    @ObservationIgnored private var zuletzt = Date.distantPast
    @ObservationIgnored private let kontext = CIContext()

    func einschalten() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return false }
        einrichten()
        warteschlange.async { [sitzung] in if !sitzung.isRunning { sitzung.startRunning() } }
        await MainActor.run { an = true }
        return true
    }

    func ausschalten() {
        warteschlange.async { [sitzung] in if sitzung.isRunning { sitzung.stopRunning() } }
        an = false
    }

    func wechseln() {
        hinten.toggle()
        einrichten()
    }

    private func einrichten() {
        sitzung.beginConfiguration()
        sitzung.automaticallyConfiguresApplicationAudioSession = false   // Ton gehört dem Anruf
        sitzung.sessionPreset = .hd1280x720
        sitzung.inputs.forEach { sitzung.removeInput($0) }
        if let g = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: hinten ? .back : .front),
           let e = try? AVCaptureDeviceInput(device: g), sitzung.canAddInput(e) {
            sitzung.addInput(e)
        }
        if sitzung.outputs.isEmpty {
            let a = AVCaptureVideoDataOutput()
            a.alwaysDiscardsLateVideoFrames = true
            a.setSampleBufferDelegate(self, queue: warteschlange)
            if sitzung.canAddOutput(a) { sitzung.addOutput(a) }
        }
        if let v = sitzung.outputs.first?.connection(with: .video) {
            if v.isVideoRotationAngleSupported(90) { v.videoRotationAngle = 90 }
            if v.isVideoMirroringSupported { v.isVideoMirrored = !hinten }
        }
        sitzung.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput puffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(zuletzt) > 2.5, let pb = CMSampleBufferGetImageBuffer(puffer) else { return }
        zuletzt = Date()
        var ci = CIImage(cvPixelBuffer: pb)
        let f = min(1, 640 / max(ci.extent.width, ci.extent.height))
        ci = ci.transformed(by: CGAffineTransform(scaleX: f, y: f))
        guard let cg = kontext.createCGImage(ci, from: ci.extent),
              let jpg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.7) else { return }
        let url = "data:image/jpeg;base64," + jpg.base64EncodedString()
        DispatchQueue.main.async { [weak self] in self?.bild?(url) }
    }
}

/// Kleine Live-Vorschau: das sieht sie gerade.
struct KameraVorschau: UIViewRepresentable {
    let sitzung: AVCaptureSession
    func makeUIView(context: Context) -> VorschauView {
        let v = VorschauView()
        v.ebene.session = sitzung
        v.ebene.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ v: VorschauView, context: Context) {}
    final class VorschauView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var ebene: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
