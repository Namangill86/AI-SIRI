import Foundation

enum AIError: LocalizedError {
    case noKey, http(Int, String), bad
    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your Anthropic API key in the SiriAI app (gear icon) first."
        case .http(let c, let m): return "API error \(c): \(m)"
        case .bad: return "Unexpected API response."
        }
    }
}

final class AIAssistant: @unchecked Sendable {
    static let shared = AIAssistant()
    var model: String { Shared.model }

    private let defaultSystem = "You are SiriAI, a helpful assistant on the user's iPhone. You can use tools to create reminders and calendar events, save and search notes, read device status and copy text. Use tools when the user asks for those actions. Be concise."

    /// One-shot question (used by Siri / Shortcuts).
    func ask(_ prompt: String, system: String? = nil, tools: Bool = true) async throws -> String {
        let msgs: [[String: Any]] = [["role": "user", "content": prompt]]
        let (text, _) = try await converse(msgs, system: system, tools: tools)
        return text
    }

    /// Multi-turn with tool loop. Returns final text and updated history.
    func converse(_ history: [[String: Any]], system: String? = nil, tools: Bool = true) async throws -> (String, [[String: Any]]) {
        let key = Shared.apiKey
        guard !key.isEmpty else { throw AIError.noKey }
        var messages = history
        var finalText = ""
        for _ in 0..<6 {
            var body: [String: Any] = [
                "model": model,
                "max_tokens": 1024,
                "system": system ?? defaultSystem,
                "messages": messages
            ]
            if tools { body["tools"] = Tools.definitions }

            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 60

            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                throw AIError.http(code, String(data: data, encoding: .utf8) ?? "")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]] else { throw AIError.bad }

            messages.append(["role": "assistant", "content": content])
            finalText = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")

            guard json["stop_reason"] as? String == "tool_use" else { break }

            var results: [[String: Any]] = []
            for block in content where block["type"] as? String == "tool_use" {
                let out = await Tools.run(block["name"] as? String ?? "", block["input"] as? [String: Any] ?? [:])
                results.append(["type": "tool_result", "tool_use_id": block["id"] as? String ?? "", "content": out])
            }
            messages.append(["role": "user", "content": results])
        }
        return (finalText, messages)
    }
}
