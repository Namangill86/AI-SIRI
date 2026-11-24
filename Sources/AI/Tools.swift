import Foundation
import EventKit
import UIKit
import UserNotifications

/// Device actions the AI can call (same kind of things people ask Siri to do).
enum Tools {
    static let definitions: [[String: Any]] = [
        tool("create_reminder", "Create a reminder in the Reminders app.",
             ["title": str("Reminder text"),
              "due_iso": str("Optional due date-time, ISO 8601 local, e.g. 2026-11-14T09:00:00")],
             required: ["title"]),
        tool("create_event", "Create a calendar event.",
             ["title": str("Event title"),
              "start_iso": str("Start, ISO 8601 local"),
              "end_iso": str("Optional end, ISO 8601 local; default 1 hour")],
             required: ["title", "start_iso"]),
        tool("get_today_events", "List today's calendar events.", [:], required: []),
        tool("save_note", "Save a quick note.", ["text": str("Note text")], required: ["text"]),
        tool("search_notes", "Search saved notes (empty query lists recent).",
             ["query": str("Search text")], required: []),
        tool("get_device_status", "Get battery level and current date/time.", [:], required: []),
        tool("copy_to_clipboard", "Copy text to the clipboard.", ["text": str("Text")], required: ["text"]),
        tool("open_app", "Open another app on the iPhone by name (WhatsApp, Maps, Spotify, Instagram, Swiggy, GPay, Settings...) or by URL scheme.",
             ["name": str("App name"), "url": str("Optional URL or URL scheme, e.g. whatsapp://send?text=hi")], required: ["name"]),
        tool("run_shortcut", "Run one of the user's Apple Shortcuts by name. This is how to control other apps' actions.",
             ["name": str("Exact shortcut name"), "input": str("Optional text input")], required: ["name"]),
        tool("ask_laptop", "Send a request to the AI agent on the user's laptop (open laptop apps, take a screenshot, send/receive files, control media) and return its answer.",
             ["text": str("What to ask the laptop to do")], required: ["text"]),
        tool("schedule_notification", "Schedule a local notification from SiriAI at a future time.",
             ["title": str("Title"), "body": str("Body"), "when_iso": str("Local ISO 8601 date-time")],
             required: ["title", "when_iso"])
    ]

    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func tool(_ name: String, _ desc: String, _ props: [String: Any], required: [String]) -> [String: Any] {
        ["name": name, "description": desc,
         "input_schema": ["type": "object", "properties": props, "required": required] as [String: Any]]
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        for f in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            let df = DateFormatter(); df.dateFormat = f; df.locale = Locale(identifier: "en_US_POSIX")
            if let d = df.date(from: s) { return d }
        }
        return nil
    }

    static func run(_ name: String, _ input: [String: Any]) async -> String {
        do {
            switch name {
            case "create_reminder":
                let store = EKEventStore()
                guard try await store.requestFullAccessToReminders() else { return "Reminders access denied." }
                let r = EKReminder(eventStore: store)
                r.title = input["title"] as? String ?? "Reminder"
                r.calendar = store.defaultCalendarForNewReminders()
                if let due = parseDate(input["due_iso"] as? String) {
                    r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                    r.addAlarm(EKAlarm(absoluteDate: due))
                }
                try store.save(r, commit: true)
                return "Reminder created."
            case "create_event":
                let store = EKEventStore()
                guard try await store.requestFullAccessToEvents() else { return "Calendar access denied." }
                guard let start = parseDate(input["start_iso"] as? String) else { return "Invalid start time." }
                let e = EKEvent(eventStore: store)
                e.title = input["title"] as? String ?? "Event"
                e.startDate = start
                e.endDate = parseDate(input["end_iso"] as? String) ?? start.addingTimeInterval(3600)
                e.calendar = store.defaultCalendarForNewEvents
                try store.save(e, span: .thisEvent)
                return "Event created."
            case "get_today_events":
                let store = EKEventStore()
                guard try await store.requestFullAccessToEvents() else { return "Calendar access denied." }
                let s = Calendar.current.startOfDay(for: Date())
                let e = Calendar.current.date(byAdding: .day, value: 1, to: s)!
                let evs = store.events(matching: store.predicateForEvents(withStart: s, end: e, calendars: nil))
                if evs.isEmpty { return "No events today." }
                let f = DateFormatter(); f.timeStyle = .short
                return evs.map { "\(f.string(from: $0.startDate)) \($0.title ?? "")" }.joined(separator: "\n")
            case "save_note":
                NotesStore.add(input["text"] as? String ?? "")
                return "Note saved."
            case "search_notes":
                let n = NotesStore.search(input["query"] as? String ?? "")
                return n.isEmpty ? "No notes found." : n.map { "- " + $0.text }.joined(separator: "\n")
            case "get_device_status":
                let level = await MainActor.run { () -> Float in
                    UIDevice.current.isBatteryMonitoringEnabled = true
                    return UIDevice.current.batteryLevel
                }
                let pct = level < 0 ? "unknown" : "\(Int(level * 100))%"
                return "Battery: \(pct). Now: \(Date().formatted(date: .complete, time: .shortened))."
            case "copy_to_clipboard":
                let t = input["text"] as? String ?? ""
                await MainActor.run { UIPasteboard.general.string = t }
                return "Copied."
            case "open_app":
                let name = input["name"] as? String ?? ""
                guard let url = AppLinks.url(for: name, raw: input["url"] as? String) else {
                    return "No link known for \"\(name)\". Try run_shortcut or pass a URL scheme."
                }
                return await open(url)
            case "run_shortcut":
                var c = URLComponents(string: "shortcuts://run-shortcut")!
                c.queryItems = [URLQueryItem(name: "name", value: input["name"] as? String ?? "")]
                if let t = input["input"] as? String, !t.isEmpty {
                    c.queryItems?.append(URLQueryItem(name: "input", value: "text"))
                    c.queryItems?.append(URLQueryItem(name: "text", value: t))
                }
                guard let url = c.url else { return "Bad shortcut name." }
                return await open(url)
            case "ask_laptop":
                return try await RelayLink.ask(input["text"] as? String ?? "")
            case "schedule_notification":
                let center = UNUserNotificationCenter.current()
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { return "Notification permission denied." }
                guard let date = parseDate(input["when_iso"] as? String), date > Date() else { return "Invalid or past time." }
                let c = UNMutableNotificationContent()
                c.title = input["title"] as? String ?? "SiriAI"
                c.body = input["body"] as? String ?? ""
                c.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: trig))
                return "Notification scheduled."
            default:
                return "Unknown tool."
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}
