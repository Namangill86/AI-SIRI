import WidgetKit
import SwiftUI
import AppIntents

struct SiriEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
}

struct SiriProvider: TimelineProvider {
    func placeholder(in context: Context) -> SiriEntry { SiriEntry(date: .now, state: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SiriEntry) -> Void) {
        completion(SiriEntry(date: .now, state: context.isPreview ? .sample : WidgetStateStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SiriEntry>) -> Void) {
        completion(Timeline(entries: [SiriEntry(date: .now, state: WidgetStateStore.load())], policy: .never))
    }
}

struct SiriWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SiriEntry
    private var s: WidgetState { entry.state }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "sparkles").font(.title2).widgetURL(URL(string: "siriai://ask"))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(s.thinking ? "Thinking…" : s.title, systemImage: "sparkles").font(.headline)
                Text(s.answer.isEmpty ? "Tap to ask SiriAI" : s.answer).font(.caption).lineLimit(3)
            }
            .widgetURL(URL(string: "siriai://ask"))
        case .systemMedium:
            HStack(spacing: 14) {
                answerBlock
                VStack(spacing: 8) {
                    HStack(spacing: 8) { chip(.plan); chip(.motivate) }
                    HStack(spacing: 8) { chip(.fact); chip(.idea) }
                    Link(destination: URL(string: "siriai://ask")!) {
                        Label("Ask", systemImage: "mic.fill").font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(.white, in: Capsule()).foregroundStyle(.indigo)
                    }
                }
                .frame(width: 150)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                answerBlock
                HStack(spacing: 6) {
                    ForEach([QuickPrompt.plan, .motivate, .fact, .idea], id: \.self) { iconChip($0) }
                }
            }
        }
    }

    private var answerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .symbolEffect(.variableColor.iterative, isActive: s.thinking)
                Text(s.thinking ? "Thinking…" : s.title).font(.caption.weight(.bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            Text(s.thinking ? "One moment" : (s.answer.isEmpty ? "Tap a button. No need to open the app." : s.answer))
                .font(.system(size: family == .systemSmall ? 12 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(family == .systemSmall ? 4 : 5)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ p: QuickPrompt) -> some View {
        Button(intent: QuickPromptIntent(prompt: p)) {
            Label(p.title, systemImage: p.symbol)
                .font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(.white.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain).foregroundStyle(.white)
    }

    private func iconChip(_ p: QuickPrompt) -> some View {
        Button(intent: QuickPromptIntent(prompt: p)) {
            Image(systemName: p.symbol).font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(.white.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain).foregroundStyle(.white)
    }
}

struct SiriAIWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SiriAIWidget", provider: SiriProvider()) { entry in
            SiriWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.25, green: 0.18, blue: 0.75),
                                            Color(red: 0.55, green: 0.2, blue: 0.7),
                                            Color(red: 0.1, green: 0.5, blue: 0.8)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .widgetURL(URL(string: "siriai://ask"))
        }
        .configurationDisplayName("SiriAI")
        .description("Get quick AI answers right from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

@main
struct SiriAIWidgets: WidgetBundle {
    var body: some Widget { SiriAIWidget() }
}
