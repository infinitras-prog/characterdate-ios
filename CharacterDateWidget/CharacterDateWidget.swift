import SwiftUI
import WidgetKit

/// Home-Bildschirm-Widget: wer dir zuletzt geschrieben hat. Klein = ein Chat, Mittel = bis zu drei.
struct ChatEintrag: TimelineEntry {
    let date: Date
    let chats: [WidgetChat]
}

private let beispiel = [
    WidgetChat(id: "a", name: "Lina", text: "Bin gleich zuhause, ruf mich an? 💕", vonIhr: true, zeit: Date().timeIntervalSince1970 - 120, online: "ja"),
    WidgetChat(id: "b", name: "Mia", text: "Haha, genau so war's 😄", vonIhr: true, zeit: Date().timeIntervalSince1970 - 3600, online: "kurz"),
]

struct ChatAnbieter: TimelineProvider {
    func placeholder(in context: Context) -> ChatEintrag { ChatEintrag(date: Date(), chats: beispiel) }

    func getSnapshot(in context: Context, completion: @escaping (ChatEintrag) -> Void) {
        let c = Widgetdaten.chats()
        completion(ChatEintrag(date: Date(), chats: context.isPreview || c.isEmpty ? beispiel : c))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChatEintrag>) -> Void) {
        // Die App stößt das Neuladen an, sobald etwas Neues da ist; sonst halbstündlich (für »vor x Min.«)
        let jetzt = Date()
        completion(Timeline(entries: [ChatEintrag(date: jetzt, chats: Widgetdaten.chats())],
                            policy: .after(jetzt.addingTimeInterval(30 * 60))))
    }
}

private let rose = Color(red: 0.94, green: 0.39, blue: 0.71)
private let violett = Color(red: 0.64, green: 0.42, blue: 0.98)

struct Rund: View {
    let chat: WidgetChat
    let groesse: CGFloat
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let b = Widgetdaten.bild(chat.id) {
                    Image(uiImage: b).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [rose, violett], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Text(String(chat.name.prefix(1))).font(.system(size: groesse * 0.42, weight: .semibold)).foregroundStyle(.white))
                }
            }
            .frame(width: groesse, height: groesse).clipShape(Circle())
            Circle().fill(chat.online == "ja" ? Color.green : chat.online == "kurz" ? .orange : .gray)
                .frame(width: groesse * 0.26, height: groesse * 0.26)
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
        }
    }
}

struct ChatWidgetAnsicht: View {
    @Environment(\.widgetFamily) private var familie
    let e: ChatEintrag

    var body: some View {
        Group {
            if e.chats.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.title2).foregroundStyle(rose)
                    Text("Öffne CharacterDate einmal, dann erscheinen hier deine Chats.")
                        .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
                }
            } else if familie == .systemSmall, let c = e.chats.first {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Rund(chat: c, groesse: 44); Spacer() }
                    Text(c.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(c.text.isEmpty ? "Schreib ihr 💬" : c.text).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                    Spacer(minLength: 0)
                    Text(Date(timeIntervalSince1970: c.zeit), style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                .widgetURL(URL(string: "characterdate://chat/\(c.id)"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(e.chats.prefix(3)) { c in
                        Link(destination: URL(string: "characterdate://chat/\(c.id)")!) {
                            HStack(spacing: 10) {
                                Rund(chat: c, groesse: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack {
                                        Text(c.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                        Spacer()
                                        Text(Date(timeIntervalSince1970: c.zeit), style: .relative)
                                            .font(.caption2).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                    }
                                    Text((c.vonIhr ? "" : "Du: ") + (c.text.isEmpty ? "…" : c.text))
                                        .font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.11, green: 0.09, blue: 0.17), Color(red: 0.2, green: 0.1, blue: 0.24)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

struct ChatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CharacterDateChats", provider: ChatAnbieter()) { e in ChatWidgetAnsicht(e: e) }
            .configurationDisplayName("Chats")
            .description("Wer dir zuletzt geschrieben hat.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CharacterDateWidgets: WidgetBundle {
    var body: some Widget { ChatWidget() }
}
