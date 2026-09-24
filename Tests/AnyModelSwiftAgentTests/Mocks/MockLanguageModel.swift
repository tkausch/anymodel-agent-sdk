import Foundation
@testable import AnyModelSwiftAgentSDK
import AnyLanguageModel

/// A scripted `LanguageModel` used to drive `Agent` in tests without making
/// real network calls. Each request consumes the next scripted step, in order,
/// and records the transcript the model was sent.
///
/// Like the Anthropic and Ollama backends, a tool-call step executes one round of
/// tools and returns without a text reply.
final class MockLanguageModel: LanguageModel, @unchecked Sendable {
    typealias UnavailableReason = Never

    enum Step {
        /// Reply with plain text, ending the model's turn.
        case text(String)
        /// Call a tool with the given JSON arguments.
        case toolCall(id: String, name: String, argumentsJSON: String)
    }

    struct MockError: Error {}

    private(set) var recordedTranscripts: [Transcript] = []
    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        recordedTranscripts.append(session.transcript)
        guard !steps.isEmpty else { throw MockError() }

        switch steps.removeFirst() {
        case .text(let text):
            return LanguageModelSession.Response(
                content: text as! Content,
                rawContent: GeneratedContent(text),
                transcriptEntries: []
            )
        case .toolCall(let id, let name, let argumentsJSON):
            let call = Transcript.ToolCall(id: id, toolName: name, arguments: try GeneratedContent(json: argumentsJSON))

            let result: String
            if let tool = session.tools.first(where: { $0.name == name }) {
                result = try await Self.call(tool, arguments: call.arguments)
            } else {
                result = "Tool not found: \(name)"
            }
            let output = Transcript.ToolOutput(id: id, toolName: name, segments: [.text(.init(content: result))])

            return LanguageModelSession.Response(
                content: "" as! Content,
                rawContent: GeneratedContent(""),
                transcriptEntries: [.toolCalls(Transcript.ToolCalls([call])), .toolOutput(output)]
            )
        }
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        fatalError("not used in tests")
    }

    private static func call(_ tool: some Tool, arguments: GeneratedContent) async throws -> String {
        let output = try await tool.call(arguments: .init(arguments))
        return output.promptRepresentation.description
    }
}

// MARK: - Transcript helpers

extension Transcript {
    /// Text of every prompt entry, in order.
    var promptTexts: [String] {
        compactMap { entry in
            guard case .prompt(let prompt) = entry else { return nil }
            return prompt.segments.texts.joined()
        }
    }

    /// Text of every tool output entry, in order.
    var toolOutputTexts: [String] {
        compactMap { entry in
            guard case .toolOutput(let output) = entry else { return nil }
            return output.segments.texts.joined()
        }
    }

    /// Text of every response entry, in order.
    var responseTexts: [String] {
        compactMap { entry in
            guard case .response(let response) = entry else { return nil }
            return response.segments.texts.joined()
        }
    }
}

private extension [Transcript.Segment] {
    var texts: [String] {
        compactMap { segment in
            if case .text(let text) = segment { return text.content }
            return nil
        }
    }
}
