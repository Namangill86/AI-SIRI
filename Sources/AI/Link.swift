import Foundation

enum LinkError: LocalizedError {
    case notConfigured
    case server(Int, String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Set the relay URL and room token in SiriAI settings (gear icon) first."
        case .server(let c, let m):
            if c == 503 { return "Your laptop is offline. Start the laptop agent." }
            if c == 401 { return "The room token was rejected by the relay." }
            return "Relay error \(c): \(m)"
        }
    }
}

/// Talks to your own relay so Siri / Shortcuts / the app can reach the laptop agent.
enum RelayLink {
    static func request(_ path: String, query: [String: String] = [:], json: [String: Any]? = nil,
                        raw: Data? = nil, timeout: TimeInterval = 100) async throws -> Data {
        let base = Shared.relay.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !base.isEmpty, !Shared.roomToken.isEmpty, var c = URLComponents(string: base + path) else { throw LinkError.notConfigured }
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = c.url else { throw LinkError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue(Shared.roomToken, forHTTPHeaderField: "x-room-token")

        let data: Data, resp: URLResponse
        if let raw {
            req.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
            (data, resp) = try await URLSession.shared.upload(for: req, from: raw)
        } else {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json ?? [:])
            (data, resp) = try await URLSession.shared.data(for: req)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw LinkError.server(code, String(data: data, encoding: .utf8) ?? "") }
        return data
    }

    /// Ask the AI running on the laptop and wait for its answer.
    static func ask(_ text: String) async throws -> String {
        let d = try await request("/ask", json: ["text": text, "to": Shared.laptopName, "from": Shared.deviceName])
        let j = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        return j?["reply"] as? String ?? "No reply."
    }

    static func sendFile(_ data: Data, name: String, mime: String) async throws {
        _ = try await request("/upload",
                              query: ["name": name, "mime": mime, "from": Shared.deviceName, "to": Shared.laptopName],
                              raw: data, timeout: 300)
    }

    static func notifyLaptop(title: String, body: String) async throws {
        _ = try await request("/n", json: ["title": title, "body": body, "app": "iPhone", "to": Shared.laptopName])
    }
}
