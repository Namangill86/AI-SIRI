import AppIntents
import WidgetKit

enum QuickPrompt: String, AppEnum {
    case plan, motivate, fact, idea

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Quick Prompt"
    static var caseDisplayRepresentations: [QuickPrompt: DisplayRepresentation] = [
        .plan: "Plan my day", .motivate: "Motivate me", .fact: "Fun fact", .idea: "Idea"
    ]

    var title: String {
        switch self {
        case .plan: return "Plan"
        case .motivate: return "Motivate"
        case .fact: return "Fact"
        case .idea: return "Idea"
        }
    }
    var symbol: String {
        switch self {
        case .plan: return "checklist"
        case .motivate: return "flame.fill"
        case .fact: return "lightbulb.fill"
        case .idea: return "wand.and.stars"
        }
    }
    var text: String {
        switch self {
        case .plan: return "Give me a simple 3-step plan for a productive day."
        case .motivate: return "Give me one short, energising motivational line."
        case .fact: return "Tell me one surprising fun fact."
        case .idea: return "Give me one creative idea for a small weekend project."
        }
    }
}

/// Runs straight from the home-screen widget, no app launch.
struct QuickPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Prompt"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Prompt") var prompt: QuickPrompt

    init() {}
    init(prompt: QuickPrompt) { self.prompt = prompt }

    func perform() async throws -> some IntentResult {
        WidgetStateStore.save(.init(thinking: true, title: prompt.title, answer: "", date: .now))
        WidgetCenter.shared.reloadAllTimelines()
        var out = WidgetState(thinking: false, title: prompt.title, answer: "", date: .now)
        do {
            out.answer = try await AIAssistant.shared.ask(
                prompt.text,
                system: "You write for a tiny phone widget. Max 30 words, plain text, no markdown.",
                tools: false)
        } catch {
            out.answer = error.localizedDescription
        }
        WidgetStateStore.save(out)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
