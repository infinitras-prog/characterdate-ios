import SwiftUI
import Observation

/// Videoanruf: lebendiges Gesicht vom PC (LivePortrait) – Kopf, Augen und Lippen wie bei einem VTuber, fotorealistisch.
/// Der PC schickt JPEG-Bilder über /ws/gesicht/{id}; hier wird immer nur das neueste gezeigt (kein Stau).
@MainActor
@Observable
final class GesichtStrom {
    var bild: UIImage?
    var vorher: UIImage?       // das Bild davor – das neue blendet weich darüber (flüssig statt ruckelig)
    var nummer = 0
    var aktiv = false          // Gesicht wird genutzt (sonst Clips/Standbild)
    var bereit = false
    @ObservationIgnored private var socket: URLSessionWebSocketTask?

    func starten(_ v: Verbindung, charId: String, bild rel: String?) {
        stoppen()
        guard let s = v.gesichtSocket(charId, bild: rel) else { aktiv = false; return }
        socket = s
        aktiv = true
        s.resume()
        empfangen(s)
    }

    func stoppen() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private func empfangen(_ s: URLSessionWebSocketTask) {
        s.receive { [weak self] ergebnis in
            Task { @MainActor in
                guard let self, self.socket === s else { return }
                switch ergebnis {
                case .failure:
                    if !self.bereit { self.aktiv = false }       // nie verbunden → zurück zu Clips/Standbild
                case .success(let n):
                    switch n {
                    case .data(let d):
                        if let b = UIImage(data: d) {
                            self.vorher = self.bild; self.bild = b; self.nummer &+= 1; self.bereit = true
                        }
                    case .string(let t):
                        if t.contains("\"fehler\"") && !self.bereit { self.aktiv = false; return }
                    @unknown default: break
                    }
                    self.empfangen(s)
                }
            }
        }
    }
}

struct LiveGesichtAnsicht: View {
    let strom: GesichtStrom
    var body: some View {
        GeometryReader { g in
            if let b = strom.bild {
                ZStack {
                    if let alt = strom.vorher {
                        Image(uiImage: alt).resizable().interpolation(.high).scaledToFill()
                            .frame(width: g.size.width, height: g.size.height).clipped()
                    }
                    Image(uiImage: b).resizable().interpolation(.high).scaledToFill()
                        .frame(width: g.size.width, height: g.size.height).clipped()
                        .id(strom.nummer)
                        .transition(.opacity)
                }
                .animation(.linear(duration: 0.055), value: strom.nummer)
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white).scaleEffect(1.2)
                    Text("verbindet Video …").font(.footnote).foregroundStyle(.white.opacity(0.75))
                }
                .frame(width: g.size.width, height: g.size.height)
            }
        }
    }
}
