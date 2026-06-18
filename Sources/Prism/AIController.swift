import SwiftUI
import Foundation

/// A single chat message shown in the AI sidebar.
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, tool, system }
    let id = UUID()
    let role: Role
    var text: String
}

/// Drives the AI sidebar: holds the conversation, talks to the selected LLM
/// provider (Claude, ChatGPT, Gemini, Perplexity, or DeepSeek), and runs an
/// agentic tool loop so the model can actually control the browser (navigate,
/// read the page, open tabs).
@MainActor
final class AIController: ObservableObject {
    @Published var messages: [ChatMessage] = [
        .init(role: .assistant, text: "I'm the Prism agent. Pick a provider and paste its API key in Settings, then give me a goal — e.g. \"open Hacker News and summarize the top story.\"")
    ]

    /// Currently selected back-end.
    @Published var provider: AIProvider = .claude
    /// Per-provider API keys (seeded from environment variables, memory-only).
    @Published var apiKeys: [String: String] = [:]
    /// Per-provider model overrides (default to each provider's `defaultModel`).
    @Published var models: [String: String] = [:]

    @Published var isThinking = false
    @Published var agentMode = true          // when on, the model may call browser tools

    private weak var browser: BrowserState?
    func attach(browser: BrowserState) { self.browser = browser }

    private let systemPrompt = "You are Prism's built-in browsing agent. Be concise. Use the provided tools to navigate and read pages when the user asks you to act on the web. Summarize what you find."

    init() {
        var keys: [String: String] = [:]
        var mods: [String: String] = [:]
        for p in AIProvider.allCases {
            keys[p.rawValue] = ProcessInfo.processInfo.environment[p.envVar] ?? ""
            mods[p.rawValue] = p.defaultModel
        }
        apiKeys = keys
        models = mods
    }

    // MARK: - Current-provider accessors

    var currentKey: String { apiKeys[provider.rawValue] ?? "" }
    var currentModel: String {
        let m = models[provider.rawValue] ?? ""
        return m.isEmpty ? provider.defaultModel : m
    }

    /// Two-way bindings the Settings UI uses for the active provider.
    func keyBinding() -> Binding<String> {
        Binding(get: { self.apiKeys[self.provider.rawValue] ?? "" },
                set: { self.apiKeys[self.provider.rawValue] = $0 })
    }
    func modelBinding() -> Binding<String> {
        Binding(get: { self.models[self.provider.rawValue] ?? self.provider.defaultModel },
                set: { self.models[self.provider.rawValue] = $0 })
    }

    // MARK: - Public entry point

    func send(_ userText: String) {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(.init(role: .user, text: trimmed))
        guard !currentKey.isEmpty else {
            messages.append(.init(role: .system, text: "No API key set for \(provider.displayName). Open Settings (⚙), choose a provider and paste its key to enable real responses."))
            return
        }
        Task { await runAgentLoop() }
    }

    // MARK: - Agent loop

    /// Sends the conversation to the selected provider. If the model requests a
    /// tool, we run it, feed the result back, and repeat until it returns a
    /// normal answer.
    private func runAgentLoop() async {
        isThinking = true
        defer { isThinking = false }

        // Build a normalized history from our chat transcript. We drop any
        // leading assistant/system lines so the conversation starts with a user
        // turn (required by Anthropic and Gemini).
        var history: [AgentItem] = []
        for msg in messages {
            switch msg.role {
            case .user:
                history.append(.user(msg.text))
            case .assistant:
                if !history.isEmpty { history.append(.assistant(text: msg.text, toolCalls: [])) }
            default:
                break
            }
        }

        for _ in 0..<6 {   // cap tool iterations to avoid runaway loops
            do {
                let response = try await callProvider(history)

                // Surface any assistant text immediately.
                if let text = response.text, !text.isEmpty {
                    messages.append(.init(role: .assistant, text: text))
                }

                guard agentMode, !response.toolCalls.isEmpty else { return }

                // Record the assistant's tool-call turn in history.
                history.append(.assistant(text: response.text, toolCalls: response.toolCalls))

                // Run each requested tool and collect the results.
                var results: [AgentToolResult] = []
                for call in response.toolCalls {
                    messages.append(.init(role: .tool, text: "→ \(call.name)(\(call.summary))"))
                    let result = await runTool(call)
                    results.append(.init(id: call.id, name: call.name, content: result))
                }
                history.append(.toolResults(results))
            } catch {
                messages.append(.init(role: .system, text: "⚠︎ \(provider.displayName) error: \(error.localizedDescription)"))
                return
            }
        }
    }

    // MARK: - Tools the agent can call

    private func runTool(_ tool: AgentToolCall) async -> String {
        guard let browser else { return "Browser unavailable." }
        switch tool.name {
        case "navigate":
            let url = tool.arguments["url"] as? String ?? ""
            browser.go(to: url)
            try? await Task.sleep(nanoseconds: 1_800_000_000) // let the page load
            return "Navigated to \(url)."
        case "open_tab":
            let url = tool.arguments["url"] as? String
            browser.newTab(url: url)
            return "Opened a new tab\(url != nil ? " at \(url!)" : "")."
        case "read_page":
            let text = await browser.readCurrentPageText()
            return String(text.prefix(8000))   // keep token usage sane
        case "go_back":
            browser.goBack(); return "Went back."
        default:
            return "Unknown tool \(tool.name)."
        }
    }

    /// Browser tools in a provider-neutral form (converted per provider below).
    private var toolDefs: [ToolDef] {
        [
            ToolDef(name: "navigate", description: "Load a URL or web search in the current tab.",
                    parameters: ["type": "object",
                                 "properties": ["url": ["type": "string"]] as [String: Any],
                                 "required": ["url"]]),
            ToolDef(name: "open_tab", description: "Open a new browser tab, optionally at a URL.",
                    parameters: ["type": "object",
                                 "properties": ["url": ["type": "string"]] as [String: Any]]),
            ToolDef(name: "read_page", description: "Return the visible text of the current page.",
                    parameters: ["type": "object", "properties": [String: Any]()]),
            ToolDef(name: "go_back", description: "Navigate back in history.",
                    parameters: ["type": "object", "properties": [String: Any]()])
        ]
    }

    // MARK: - Provider dispatch

    private func callProvider(_ history: [AgentItem]) async throws -> (text: String?, toolCalls: [AgentToolCall]) {
        let key = currentKey
        let model = currentModel
        let useTools = agentMode && provider.supportsTools

        switch provider.apiStyle {
        case .anthropic: return try await callAnthropic(history, key: key, model: model, useTools: useTools)
        case .openai:    return try await callOpenAI(history, key: key, model: model, useTools: useTools)
        case .gemini:    return try await callGemini(history, key: key, model: model, useTools: useTools)
        }
    }

    // MARK: - Anthropic (Claude)

    private func callAnthropic(_ history: [AgentItem], key: String, model: String, useTools: Bool) async throws -> (text: String?, toolCalls: [AgentToolCall]) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": anthropicMessages(history)
        ]
        if useTools {
            body["tools"] = toolDefs.map {
                ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] as [String: Any]
            }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else { throw malformed() }

        var text: String?
        var calls: [AgentToolCall] = []
        for block in content {
            switch block["type"] as? String {
            case "text":
                text = (text ?? "") + ((block["text"] as? String) ?? "")
            case "tool_use":
                calls.append(AgentToolCall(id: block["id"] as? String ?? "",
                                           name: block["name"] as? String ?? "",
                                           arguments: block["input"] as? [String: Any] ?? [:]))
            default: break
            }
        }
        return (text, calls)
    }

    private func anthropicMessages(_ history: [AgentItem]) -> [[String: Any]] {
        history.map { item -> [String: Any] in
            switch item {
            case .user(let t):
                return ["role": "user", "content": t]
            case .assistant(let text, let calls):
                var content: [[String: Any]] = []
                if let text, !text.isEmpty { content.append(["type": "text", "text": text]) }
                for c in calls {
                    content.append(["type": "tool_use", "id": c.id, "name": c.name, "input": c.arguments])
                }
                return ["role": "assistant", "content": content]
            case .toolResults(let results):
                let content: [[String: Any]] = results.map {
                    ["type": "tool_result", "tool_use_id": $0.id, "content": $0.content]
                }
                return ["role": "user", "content": content]
            }
        }
    }

    // MARK: - OpenAI-compatible (ChatGPT, Perplexity, DeepSeek)

    private func callOpenAI(_ history: [AgentItem], key: String, model: String, useTools: Bool) async throws -> (text: String?, toolCalls: [AgentToolCall]) {
        var req = URLRequest(url: URL(string: provider.chatEndpoint)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": openAIMessages(history)
        ]
        if useTools {
            body["tools"] = toolDefs.map {
                ["type": "function",
                 "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters] as [String: Any]] as [String: Any]
            }
            body["tool_choice"] = "auto"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { throw malformed() }

        let text = message["content"] as? String
        var calls: [AgentToolCall] = []
        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for tc in toolCalls {
                let id = tc["id"] as? String ?? UUID().uuidString
                let fn = tc["function"] as? [String: Any] ?? [:]
                let name = fn["name"] as? String ?? ""
                let argString = fn["arguments"] as? String ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(argString.utf8))) as? [String: Any] ?? [:]
                calls.append(AgentToolCall(id: id, name: name, arguments: args))
            }
        }
        return (text, calls)
    }

    private func openAIMessages(_ history: [AgentItem]) -> [[String: Any]] {
        var msgs: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        for item in history {
            switch item {
            case .user(let t):
                msgs.append(["role": "user", "content": t])
            case .assistant(let text, let calls):
                var m: [String: Any] = ["role": "assistant", "content": text ?? ""]
                if !calls.isEmpty {
                    m["tool_calls"] = calls.map { c in
                        ["id": c.id, "type": "function",
                         "function": ["name": c.name, "arguments": jsonString(c.arguments)] as [String: Any]] as [String: Any]
                    }
                }
                msgs.append(m)
            case .toolResults(let results):
                for r in results {
                    msgs.append(["role": "tool", "tool_call_id": r.id, "content": r.content])
                }
            }
        }
        return msgs
    }

    // MARK: - Gemini (Google)

    private func callGemini(_ history: [AgentItem], key: String, model: String, useTools: Bool) async throws -> (text: String?, toolCalls: [AgentToolCall]) {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)"
        guard let url = URL(string: urlString) else { throw malformed() }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "contents": geminiContents(history),
            "systemInstruction": ["parts": [["text": systemPrompt]]] as [String: Any],
            "generationConfig": ["maxOutputTokens": 1024] as [String: Any]
        ]
        if useTools {
            body["tools"] = [["functionDeclarations": toolDefs.map {
                ["name": $0.name, "description": $0.description, "parameters": $0.parameters] as [String: Any]
            }] as [String: Any]]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { throw malformed() }

        var text: String?
        var calls: [AgentToolCall] = []
        for part in parts {
            if let t = part["text"] as? String { text = (text ?? "") + t }
            if let fc = part["functionCall"] as? [String: Any] {
                let name = fc["name"] as? String ?? ""
                let args = fc["args"] as? [String: Any] ?? [:]
                // Gemini function calls carry no id; key the result by name.
                calls.append(AgentToolCall(id: name, name: name, arguments: args))
            }
        }
        return (text, calls)
    }

    private func geminiContents(_ history: [AgentItem]) -> [[String: Any]] {
        history.map { item -> [String: Any] in
            switch item {
            case .user(let t):
                return ["role": "user", "parts": [["text": t]]]
            case .assistant(let text, let calls):
                var parts: [[String: Any]] = []
                if let text, !text.isEmpty { parts.append(["text": text]) }
                for c in calls { parts.append(["functionCall": ["name": c.name, "args": c.arguments] as [String: Any]]) }
                return ["role": "model", "parts": parts]
            case .toolResults(let results):
                let parts: [[String: Any]] = results.map {
                    ["functionResponse": ["name": $0.name, "response": ["result": $0.content] as [String: Any]] as [String: Any]]
                }
                return ["role": "user", "parts": parts]
            }
        }
    }

    // MARK: - Shared networking helpers

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "status \(http.statusCode)"
            throw NSError(domain: "Prism.AI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return data
    }

    private func malformed() -> Error {
        NSError(domain: "Prism.AI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed response"])
    }

    private func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}
