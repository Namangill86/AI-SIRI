import Foundation

struct Note: Codable, Identifiable {
    var id = UUID()
    var text: String
    var date = Date()
}

enum NotesStore {
    private static let key = "notes.v1"

    static func all() -> [Note] {
        guard let d = Shared.defaults.data(forKey: key),
              let n = try? JSONDecoder().decode([Note].self, from: d) else { return [] }
        return n
    }

    static func add(_ text: String) {
        var n = all()
        n.insert(Note(text: text), at: 0)
        if let d = try? JSONEncoder().encode(n) { Shared.defaults.set(d, forKey: key) }
    }

    static func search(_ q: String) -> [Note] {
        let all = all()
        if q.isEmpty { return Array(all.prefix(10)) }
        return all.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }
}
