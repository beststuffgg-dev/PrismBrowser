import SwiftUI
import Foundation

/// A single chat message shown in the AI sidebar.
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, tool, system }
    let id = UUID()
    let role: Role
    var text: String
}

/// Drives the AI sidebar: holds the conversation, talks to the Anthropic
/// Messages API, and runs an agentic tool loop so the model can actually
/// control the browser (navigate, read the page, open tabs).
@MainActor
final class AIController: ObservableObject {
    @Published var messages: [ChatMessage] = [
        .init(role: .assistant, text: "I'm the Prism agent. Give me a goal — e.g. \"open Hacker News and summarize the top story\" — and paste your Anthropic API key in Settings to let me act.")
    ]
    @Published var apiKey: String = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    @Published var model: String = "claude-sonnet-4-5"
    @Published var isThinking = false
    @Published var agentMode = true          // when on, the model may call browser tools

    private weak var browser: BrowserState?
    func attach(browser: BrowserState) { self.browser = browser }

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Public entry point

    func send(_ userText: String) {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(.init(role: .user, text: trimmed))
        guard !apiKey.isEmpty else {
            messages.append(.init(role: .system, text: "No API key set. Open Settings (⚙) and paste your Anthropic key to enable real responses."))
            return
        }
        Task { await runAgentLoop() }
    }

    // MARK: - Agent loop

    /// Sends the conversation to Claude. If the model requests a tool, we run it,
    /// feed the result back, and repeat until it returns a normal answer.
    private func runAgentLoop() async {
        isThinking = true
        defer { isThinking = false }

        // Build the running API message list from our chat history.
        var apiMessages: [[String: Any]] = messages.compactMap { msg in
            switch msg.role {
            case .user:      return ["role": "user", "content": msg.text] as [String: Any]
            case .assistant: return ["role": "assistant", "content": msg.text] as [String: Any]
            default:         return nil
            }
        }

        for _ in 0..<6 {   // cap tool iterations to avoid runaway loops
            do {
                let response = try await callAPI(apiMessages)
                // Surface any text blocks immediately.
                if let text = response.text, !text.isEmpty {
                    messages.append(.init(role: .assistant, text: text))
                }
                guard agentMode, let toolUse = response.toolUse else { return }

                // Echo the tool action in the transcript.
                messages.append(.init(role: .tool, text: "→ \(toolUse.name)(\(toolUse.inputSummary))"))

                let result = await runTool(toolUse)

                // Append the assistant's tool_use turn + our tool_result turn.
                apiMessages.append(["role": "assistant", "content": response.rawContent])
                apiMessages.append(["role": "user", "content": [[
                    "type": "tool_result",
                    "tool_use_id": toolUse.id,
                    "content": result
                ]]])
            } catch {
                messages.append(.init(role: .system, text: "⚠︎ API error: \(error.localizedDescription)"))
                return
            }
        }
    }

    // MARK: - Tools the agent can call

    private func runTool(_ tool: ToolUse) async -> String {
        guard let browser else { return "Browser unavailable." }
        switch tool.name {
        case "navigate":
            let url = tool.input["url"] as? String ?? ""
            browser.go(to: url)
            try? await Task.sleep(nanoseconds: 1_800_000_000) // let the page load
            return "Navigated to \(url)."
        case "open_tab":
            let url = tool.input["url"] as? String
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

    private var toolSchema: [[String: Any]] {
        [
            ["name": "navigate", "description": "Load a URL or web search in the current tab.",
             "input_schema": ["type": "object", "properties": ["url": ["type": "string"]], "required": ["url"]]],
            ["name": "open_tab", "description": "Open a new browser tab, optionally at a URL.",
             "input_schema": ["type": "object", "properties": ["url": ["type": "string"]]]],
            ["name": "read_page", "description": "Return the visible text of the current page.",
             "input_schema": ["type": "object", "properties": [:]]],
            ["name": "go_back", "description": "Navigate back in history.",
             "input_schema": ["type": "object", "properties": [:]]]
        ]
    }

    // MARK: - Networking

    struct ToolUse {
        let id: String
        let name: String
        let input: [String: Any]
        var inputSummary: String {
            input.map { "\($0)=\($1)" }.joined(separator: ", ")
        }
    }
    struct APIResponse {
        var text: String?
        var toolUse: ToolUse?
        var rawContent: [[String: Any]]
    }

    private func callAPI(_ apiMessages: [[String: Any]]) async throws -> APIResponse {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": "You are Prism's built-in browsing agent. Be concise. Use the provided tools to navigate and read pages when the user asks you to act on the web. Summarize what you find.",
            "tools": agentMode ? toolSchema : [],
            "messages": apiMessages
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "status \(http.statusCode)"
            throw NSError(domain: "Anthropic", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw NSError(domain: "Anthropic", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Malformed response"])
        }

        var text: String?
        var toolUse: ToolUse?
        for block in content {
            switch block["type"] as? String {
            case "text":
                text = (text ?? "") + ((block["text"] as? String) ?? "")
            case "tool_use":
                toolUse = ToolUse(
                    id: block["id"] as? String ?? "",
                    name: block["name"] as? String ?? "",
                    input: block["input"] as? [String: Any] ?? [:]
                )
            default: break
            }
        }
        return APIResponse(text: text, toolUse: toolUse, rawContent: content)
    }
}
