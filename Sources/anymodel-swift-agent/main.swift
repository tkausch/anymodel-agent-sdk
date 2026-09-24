import Foundation
import AnyModelSwiftAgentSDK
import AnyLanguageModel


// MARK: - Entry point

let model = makeLanguageModel()
let agent = Agent(
    model: model,
    tools: [ReadFileTool(), ListFilesTool(), GeoCodingTool(), HistoricWeatherTool()],
    options: GenerationOptions(maximumResponseTokens: 8096)
)

do {
    try await agent.run()
} catch {
    print("Error: \(error)")
    exit(1)
}

// MARK: - Helpers

/// Builds the language model selected by the environment.
///
/// - `LLM_PROVIDER`: `anthropic`, `openai`, `gemini`, `ollama` or `system`
///   (Apple Foundation Models, macOS 26+). When unset, the first provider whose
///   API key is present is used, falling back to `system`.
/// - `LLM_MODEL`: overrides the provider's default model identifier.
/// - `OLLAMA_BASE_URL`: overrides the Ollama server URL.
///
/// Exits with a clear error message if the configuration is incomplete.
func makeLanguageModel() -> any LanguageModel {
    let env = ProcessInfo.processInfo.environment
    let provider = env["LLM_PROVIDER"]?.lowercased() ?? defaultProvider(env)
    let modelID = env["LLM_MODEL"]

    switch provider {
    case "anthropic":
        let apiKey = requireEnv("ANTHROPIC_API_KEY")
        return AnthropicLanguageModel(
            apiKey: apiKey,
            model: modelID ?? "claude-opus-4-8"
        )
    case "openai":
        let apiKey = requireEnv("OPENAI_API_KEY")
        return OpenAILanguageModel(
            apiKey: apiKey,
            model: modelID ?? "gpt-5"
        )
    case "gemini":
        let apiKey = requireEnv("GEMINI_API_KEY")
        return GeminiLanguageModel(
            apiKey: apiKey,
            model: modelID ?? "gemini-2.5-flash"
        )
    case "ollama":
        let baseURL = env["OLLAMA_BASE_URL"].flatMap(URL.init(string:)) ?? OllamaLanguageModel.defaultBaseURL
        return OllamaLanguageModel(baseURL: baseURL, model: modelID ?? "qwen3")
    case "system":
        guard #available(macOS 26.0, *) else {
            fail("LLM_PROVIDER=system requires macOS 26 or newer")
        }
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            fail("Apple Foundation Models is unavailable: \(model.availability)")
        }
        return model
    default:
        fail("Unknown LLM_PROVIDER '\(provider)'. Use anthropic, openai, gemini, ollama or system.")
    }
}

/// Picks the first provider whose API key is set, otherwise the on-device model.
func defaultProvider(_ env: [String: String]) -> String {
    if env["ANTHROPIC_API_KEY"] != nil { return "anthropic" }
    if env["OPENAI_API_KEY"] != nil { return "openai" }
    if env["GEMINI_API_KEY"] != nil { return "gemini" }
    return "system"
}

func requireEnv(_ name: String) -> String {
    guard let value = ProcessInfo.processInfo.environment[name] else {
        fail("\(name) environment variable not set")
    }
    return value
}

func fail(_ message: String) -> Never {
    print("Error: \(message)")
    exit(1)
}
