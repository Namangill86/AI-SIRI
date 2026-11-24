import AppIntents
import UniformTypeIdentifiers

private let voiceSystem = "You are SiriAI answering through Siri. Reply in plain spoken language, under 60 words, no markdown. Use tools when the user asks for an action."

struct AskAIIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask AI"
    static var description = IntentDescription("Ask the AI anything. It can also set reminders, add events and save notes.")

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask?")
    var question: String

    static var parameterSummary: some ParameterSummary { Summary("Ask AI \(\.$question)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let a = try await AIAssistant.shared.ask(question, system: voiceSystem)
        return .result(value: a, dialog: IntentDialog(stringLiteral: a))
    }
}

struct SmartReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Smart Reminder"
    static var description = IntentDescription("Say a reminder in natural language, like 'call mom tomorrow at 6pm'.")

    @Parameter(title: "Reminder", requestValueDialog: "What should I remind you about, and when?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date().formatted(date: .complete, time: .shortened)
        let a = try await AIAssistant.shared.ask(
            "Current time: \(now). Create a reminder for: \(text). Then confirm in one short sentence.",
            system: voiceSystem)
        return .result(dialog: IntentDialog(stringLiteral: a))
    }
}

struct SmartEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Smart Calendar Event"
    static var description = IntentDescription("Add a calendar event from natural language.")

    @Parameter(title: "Event", requestValueDialog: "What event should I add, and when?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date().formatted(date: .complete, time: .shortened)
        let a = try await AIAssistant.shared.ask(
            "Current time: \(now). Add a calendar event: \(text). Then confirm briefly.", system: voiceSystem)
        return .result(dialog: IntentDialog(stringLiteral: a))
    }
}

struct TodayAgendaIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's Agenda"
    static var description = IntentDescription("Summarize today's calendar.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let a = try await AIAssistant.shared.ask("Read today's calendar events and summarize my day.", system: voiceSystem)
        return .result(value: a, dialog: IntentDialog(stringLiteral: a))
    }
}

struct SaveNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Note"
    static var description = IntentDescription("Save a quick note.")

    @Parameter(title: "Note", requestValueDialog: "What should I note down?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotesStore.add(text)
        return .result(dialog: "Saved.")
    }
}

struct SummarizeTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Summarize Text"
    static var description = IntentDescription("Summarize any text, e.g. passed in from Shortcuts or the clipboard.")

    @Parameter(title: "Text", requestValueDialog: "What text should I summarize?")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let a = try await AIAssistant.shared.ask("Summarize in 3 short sentences:\n\n\(text)", system: voiceSystem, tools: false)
        return .result(value: a, dialog: IntentDialog(stringLiteral: a))
    }
}

enum RewriteTone: String, AppEnum {
    case professional, friendly, shorter, formal
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tone"
    static var caseDisplayRepresentations: [RewriteTone: DisplayRepresentation] = [
        .professional: "Professional", .friendly: "Friendly", .shorter: "Shorter", .formal: "Formal"
    ]
}

struct RewriteTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Rewrite Text"
    static var description = IntentDescription("Rewrite text in a chosen tone.")

    @Parameter(title: "Text", requestValueDialog: "What text should I rewrite?")
    var text: String
    @Parameter(title: "Tone", default: .professional)
    var tone: RewriteTone

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let a = try await AIAssistant.shared.ask(
            "Rewrite in a \(tone.rawValue) tone. Return only the rewritten text:\n\n\(text)", tools: false)
        return .result(value: a)
    }
}

struct TranslateTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate Text"
    static var description = IntentDescription("Translate text into another language.")

    @Parameter(title: "Text", requestValueDialog: "What should I translate?")
    var text: String
    @Parameter(title: "Language", default: "Hindi", requestValueDialog: "Into which language?")
    var language: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let a = try await AIAssistant.shared.ask(
            "Translate into \(language). Return only the translation:\n\n\(text)", tools: false)
        return .result(value: a, dialog: IntentDialog(stringLiteral: a))
    }
}

struct OpenChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Chat"
    static var description = IntentDescription("Open the SiriAI chat.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}

struct LaunchAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open App"
    static var description = IntentDescription("Open any app by name, e.g. WhatsApp, Maps or Spotify.")
    static var openAppWhenRun = true

    @Parameter(title: "App name", requestValueDialog: "Which app should I open?")
    var appName: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await Tools.run("open_app", ["name": appName])
        return .result(dialog: IntentDialog(stringLiteral: r))
    }
}

struct RunMyShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Run My Shortcut"
    static var description = IntentDescription("Run one of your Apple Shortcuts by name.")
    static var openAppWhenRun = true

    @Parameter(title: "Shortcut name", requestValueDialog: "Which shortcut should I run?")
    var shortcutName: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await Tools.run("run_shortcut", ["name": shortcutName])
        return .result(dialog: IntentDialog(stringLiteral: r))
    }
}

struct AskLaptopIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask My Laptop"
    static var description = IntentDescription("Tell the AI on your laptop what to do: open an app, take a screenshot, send a file...")

    @Parameter(title: "Request", requestValueDialog: "What should your laptop do?")
    var request: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let a = try await Link.ask(request)
        return .result(value: a, dialog: IntentDialog(stringLiteral: a))
    }
}

struct SendToLaptopIntent: AppIntent {
    static var title: LocalizedStringResource = "Send to Laptop"
    static var description = IntentDescription("Send a file or photo to your laptop. Add this to the Share Sheet from the Shortcuts app.")

    @Parameter(title: "File")
    var file: IntentFile

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let mime = file.type?.preferredMIMEType ?? "application/octet-stream"
        try await Link.sendFile(file.data, name: file.filename, mime: mime)
        return .result(dialog: "Sent to your laptop.")
    }
}

struct SiriAIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskAIIntent(),
                    phrases: ["Ask \(.applicationName)", "Hey \(.applicationName)", "Ask \(.applicationName) a question"],
                    shortTitle: "Ask AI", systemImageName: "sparkles")
        AppShortcut(intent: SmartReminderIntent(),
                    phrases: ["Remind me with \(.applicationName)", "\(.applicationName) reminder"],
                    shortTitle: "Smart Reminder", systemImageName: "bell")
        AppShortcut(intent: SmartEventIntent(),
                    phrases: ["Add event with \(.applicationName)", "\(.applicationName) calendar"],
                    shortTitle: "Add Event", systemImageName: "calendar.badge.plus")
        AppShortcut(intent: TodayAgendaIntent(),
                    phrases: ["My day with \(.applicationName)", "\(.applicationName) agenda"],
                    shortTitle: "Today's Agenda", systemImageName: "calendar")
        AppShortcut(intent: SaveNoteIntent(),
                    phrases: ["Take a note with \(.applicationName)", "\(.applicationName) note"],
                    shortTitle: "Save Note", systemImageName: "note.text")
        AppShortcut(intent: SummarizeTextIntent(),
                    phrases: ["Summarize with \(.applicationName)"],
                    shortTitle: "Summarize", systemImageName: "text.alignleft")
        AppShortcut(intent: TranslateTextIntent(),
                    phrases: ["Translate with \(.applicationName)"],
                    shortTitle: "Translate", systemImageName: "globe")
        AppShortcut(intent: RewriteTextIntent(),
                    phrases: ["Rewrite with \(.applicationName)"],
                    shortTitle: "Rewrite", systemImageName: "pencil")
        AppShortcut(intent: AskLaptopIntent(),
                    phrases: ["Ask my laptop with \(.applicationName)", "\(.applicationName) laptop"],
                    shortTitle: "Ask Laptop", systemImageName: "laptopcomputer")
        AppShortcut(intent: LaunchAppIntent(),
                    phrases: ["Open an app with \(.applicationName)", "\(.applicationName) open app"],
                    shortTitle: "Open App", systemImageName: "square.grid.2x2")
    }
}
