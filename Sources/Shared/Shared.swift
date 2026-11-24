import Foundation

/// Storage shared by the app, Siri intents and the home-screen widget (via App Group).
enum Shared {
    static let group = "group.com.example.siriai"
    static let defaults = UserDefaults(suiteName: group) ?? .standard

    static var apiKey: String {
        get { defaults.string(forKey: "api_key") ?? "" }
        set { defaults.set(newValue, forKey: "api_key") }
    }
    static var model: String {
        get { defaults.string(forKey: "model") ?? "claude-sonnet-5-5" }
        set { defaults.set(newValue, forKey: "model") }
    }
    static var relay: String {
        get { defaults.string(forKey: "relay") ?? "" }
        set { defaults.set(newValue, forKey: "relay") }
    }
    static var roomToken: String {
        get { defaults.string(forKey: "room_token") ?? "" }
        set { defaults.set(newValue, forKey: "room_token") }
    }
    static var laptopName: String {
        get { defaults.string(forKey: "laptop_name") ?? "laptop" }
        set { defaults.set(newValue, forKey: "laptop_name") }
    }
    static var deviceName: String { "iphone" }
}

struct WidgetState: Codable {
    var thinking: Bool
    var title: String
    var answer: String
    var date: Date

    static let empty = WidgetState(thinking: false, title: "SiriAI", answer: "", date: .now)
    static let sample = WidgetState(thinking: false, title: "Plan my day",
                                    answer: "Start with your top task, then take a short walk at noon.", date: .now)
}

enum WidgetStateStore {
    private static let key = "widget.state.v1"
    static func load() -> WidgetState {
        guard let d = Shared.defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(WidgetState.self, from: d) else { return .empty }
        return s
    }
    static func save(_ s: WidgetState) {
        if let d = try? JSONEncoder().encode(s) { Shared.defaults.set(d, forKey: key) }
    }
}
