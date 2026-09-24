import Foundation
import AnyLanguageModel

/// A conversational agent that maintains a multi-turn dialogue with a language model.
///
/// `Agent` is provider-agnostic: it talks to any `LanguageModel` supported by
/// AnyLanguageModel (Anthropic, OpenAI, Gemini, Ollama, Apple Foundation Models,
/// MLX, llama.cpp, …). The underlying `LanguageModelSession` keeps the full
/// transcript and executes tool calls; the agent keeps the model running until it
/// produces a final text reply, then waits for the next user message. The
/// conversation ends when the user signals EOF.
///
/// Usage:
/// ```swift
/// let model = AnthropicLanguageModel(apiKey: apiKey, model: "claude-opus-4-8")
/// let agent = Agent(model: model, tools: [GeoCodingTool(), HistoricWeatherTool()])
/// try await agent.run()
/// ```
public actor Agent {

    /// Prompt sent when a provider returns after a tool round without a text reply.
    static let continuationPrompt = "Continue."

    // MARK: - Private state

    private let model: any LanguageModel
    private let tools: [any Tool]
    private let options: GenerationOptions
    private let terminal: any ChatTerminalProtocol
    private var session: LanguageModelSession

    // MARK: - Initialisation

    /// Creates an agent.
    /// - Parameters:
    ///   - model: The language model to converse with.
    ///   - tools: Tools made available to the model on every turn. Each call is
    ///     echoed to the terminal, and errors thrown by a tool are reported back
    ///     to the model instead of ending the turn.
    ///   - instructions: Optional system instructions for the session.
    ///   - options: Generation options (temperature, maximum response tokens, …).
    public init(
        model: any LanguageModel,
        tools: [any Tool] = [],
        instructions: String? = nil,
        options: GenerationOptions = GenerationOptions()
    ) {
        self.init(model: model, tools: tools, instructions: instructions, options: options, terminal: ChatTerminal())
    }

    /// Test-only entry point that allows substituting the terminal used for I/O,
    /// so tests can script user input and capture output without touching real stdio.
    init(
        model: any LanguageModel,
        tools: [any Tool],
        instructions: String? = nil,
        options: GenerationOptions = GenerationOptions(),
        terminal: any ChatTerminalProtocol
    ) {
        self.model = model
        self.tools = tools.map { agentTool($0, terminal: terminal) }
        self.options = options
        self.terminal = terminal
        self.session = LanguageModelSession(model: model, tools: self.tools, instructions: instructions.map(Instructions.init))
    }

    // MARK: - Public interface

    /// Starts the interactive conversation loop.
    ///
    /// Each user message is sent to the model. Tool calls are executed by the
    /// session and their results fed back, until the model replies with text.
    public func run() async throws {
        terminal.intro()

        while let input = terminal.readUserInput() {
            var response = try await session.respond(to: input, options: options)

            // Some providers (e.g. Anthropic, Ollama) execute a single tool round per
            // request and return without a text reply. Keep the model going so it can
            // act on the tool results.
            while response.content.isEmpty, response.transcriptEntries.containsToolOutput {
                response = try await continueAfterToolRound()
            }

            if !response.content.isEmpty {
                terminal.agent(response.content)
            }
        }
    }

    // MARK: - Private helpers

    /// Asks the model to continue after a tool round that produced no text.
    ///
    /// The session records an empty assistant reply for such a round, which some
    /// providers reject on the next request, so the session is rebuilt without it.
    private func continueAfterToolRound() async throws -> LanguageModelSession.Response<String> {
        let entries = session.transcript.filter { !$0.isEmptyResponse }
        session = LanguageModelSession(model: model, tools: tools, transcript: Transcript(entries: entries))
        return try await session.respond(to: Self.continuationPrompt, options: options)
    }
}

// MARK: - Transcript helpers

private extension Transcript.Entry {
    /// Whether this entry is an assistant reply without any text.
    var isEmptyResponse: Bool {
        guard case .response(let response) = self else { return false }
        return response.segments.allSatisfy { segment in
            if case .text(let text) = segment { return text.content.isEmpty }
            return false
        }
    }
}

private extension Collection<Transcript.Entry> {
    var containsToolOutput: Bool {
        contains { entry in
            if case .toolOutput = entry { return true }
            return false
        }
    }
}
