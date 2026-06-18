import Foundation

/// The set of chat/LLM back-ends Prism can talk to. Each provider maps to an
/// API "style" — Anthropic Messages, OpenAI chat-completions, or Gemini
/// generateContent. ChatGPT, Perplexity and DeepSeek all speak the
/// OpenAI-compatible dialect and differ only by endpoint, model and key.
enum AIProvider: String, CaseIterable, Identifiable {
    case claude, chatgpt, gemini, perplexity, deepseek
    var id: String { rawValue }

    /// Which wire protocol the provider uses.
    enum APIStyle { case anthropic, openai, gemini }

    var displayName: String {
        switch self {
        case .claude:     return "Claude"
        case .chatgpt:    return "ChatGPT"
        case .gemini:     return "Gemini"
        case .perplexity: return "Perplexity"
        case .deepseek:   return "DeepSeek"
        }
    }

    var apiStyle: APIStyle {
        switch self {
        case .claude:                            return .anthropic
        case .gemini:                            return .gemini
        case .chatgpt, .perplexity, .deepseek:   return .openai
        }
    }

    /// Default model id; the user can override it in Settings.
    var defaultModel: String {
        switch self {
        case .claude:     return "claude-sonnet-4-5"
        case .chatgpt:    return "gpt-4o"
        case .gemini:     return "gemini-2.0-flash"
        case .perplexity: return "sonar"
        case .deepseek:   return "deepseek-chat"
        }
    }

    /// Endpoint for OpenAI-compatible providers (ignored for the others, which
    /// build their URLs specially).
    var chatEndpoint: String {
        switch self {
        case .chatgpt:    return "https://api.openai.com/v1/chat/completions"
        case .perplexity: return "https://api.perplexity.ai/chat/completions"
        case .deepseek:   return "https://api.deepseek.com/chat/completions"
        default:          return ""
        }
    }

    /// Environment variable consulted for a pre-filled API key.
    var envVar: String {
        switch self {
        case .claude:     return "ANTHROPIC_API_KEY"
        case .chatgpt:    return "OPENAI_API_KEY"
        case .gemini:     return "GEMINI_API_KEY"
        case .perplexity: return "PERPLEXITY_API_KEY"
        case .deepseek:   return "DEEPSEEK_API_KEY"
        }
    }

    /// Whether the provider supports our agentic function-calling loop.
    /// Perplexity's API has no tool calling, so it runs as a plain chat.
    var supportsTools: Bool {
        switch self {
        case .perplexity: return false
        default:          return true
        }
    }

    /// Placeholder shown in the API-key field.
    var keyHint: String {
        switch self {
        case .claude:     return "sk-ant-…"
        case .chatgpt:    return "sk-…"
        case .gemini:     return "AIza…"
        case .perplexity: return "pplx-…"
        case .deepseek:   return "sk-…"
        }
    }
}

/// A browser tool exposed to the agent, in a provider-neutral form. Each
/// provider serializer converts this into its own tool/function schema.
struct ToolDef {
    let name: String
    let description: String
    let parameters: [String: Any]   // JSON-schema "object" describing the inputs
}

/// One tool/function call requested by the model.
struct AgentToolCall {
    let id: String
    let name: String
    let arguments: [String: Any]
    var summary: String { arguments.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") }
}

/// The outcome of running a tool, fed back to the model on the next turn.
struct AgentToolResult {
    let id: String
    let name: String
    let content: String
}

/// A provider-agnostic conversation item. History is kept in this normalized
/// form and serialized to each provider's wire format on demand.
enum AgentItem {
    case user(String)
    case assistant(text: String?, toolCalls: [AgentToolCall])
    case toolResults([AgentToolResult])
}
