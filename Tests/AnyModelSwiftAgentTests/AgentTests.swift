import Testing
@testable import AnyModelSwiftAgentSDK
import AnyLanguageModel

@Suite
struct AgentTests {

    // MARK: - Plain text turns

    @Test
    func textOnlyResponse_repliesAndPromptsForNextInput() async throws {
        // Given
        let model = MockLanguageModel(steps: [.text("Hi there!")])
        let terminal = MockChatTerminal(scriptedInputs: ["Hello", nil])
        let agent = Agent(model: model, tools: [], terminal: terminal)

        // When
        try await agent.run()

        // Then
        #expect(terminal.introCallCount == 1)
        #expect(terminal.agentMessages == ["Hi there!"])
        #expect(terminal.toolInvocations.isEmpty)
        // One read to get "Hello", one more that returns nil and ends the loop.
        #expect(terminal.readInputCallCount == 2)

        #expect(model.recordedTranscripts.count == 1)
        #expect(model.recordedTranscripts[0].promptTexts == ["Hello"])
    }

    @Test
    func immediateEOF_endsRunWithoutCallingModel() async throws {
        // Given
        let model = MockLanguageModel(steps: [])
        let terminal = MockChatTerminal(scriptedInputs: [nil])
        let agent = Agent(model: model, tools: [], terminal: terminal)

        // When
        try await agent.run()

        // Then
        #expect(terminal.readInputCallCount == 1)
        #expect(terminal.agentMessages.isEmpty)
        #expect(model.recordedTranscripts.isEmpty)
    }

    @Test
    func multipleTurns_keepConversationHistory() async throws {
        // Given
        let model = MockLanguageModel(steps: [.text("one"), .text("two")])
        let terminal = MockChatTerminal(scriptedInputs: ["first", "second", nil])
        let agent = Agent(model: model, tools: [], terminal: terminal)

        // When
        try await agent.run()

        // Then
        #expect(terminal.agentMessages == ["one", "two"])
        let secondTranscript = model.recordedTranscripts[1]
        #expect(secondTranscript.promptTexts == ["first", "second"])
        #expect(secondTranscript.responseTexts == ["one"])
    }

    // MARK: - Tool round-trips

    @Test
    func toolCall_executesToolAndSendsResultBack() async throws {
        // Given
        let model = MockLanguageModel(steps: [
            .toolCall(id: "toolu_1", name: "echo", argumentsJSON: #"{"text": "hi"}"#),
            .text("Done!"),
        ])
        let terminal = MockChatTerminal(scriptedInputs: ["do it", nil])
        let agent = Agent(model: model, tools: [EchoTool()], terminal: terminal)

        // When
        try await agent.run()

        // Then
        #expect(terminal.toolInvocations.count == 1)
        #expect(terminal.toolInvocations[0].name == "echo")
        #expect(try terminal.toolInvocations[0].arguments.value(String.self, forProperty: "text") == "hi")

        #expect(terminal.agentMessages == ["Done!"])
        // One read for "do it", one more after the tool round-trip completes.
        #expect(terminal.readInputCallCount == 2)

        // The model is asked to continue with the tool result in its history,
        // without the empty reply recorded for the tool round.
        #expect(model.recordedTranscripts.count == 2)
        let secondTranscript = model.recordedTranscripts[1]
        #expect(secondTranscript.toolOutputTexts == ["HI"])
        #expect(secondTranscript.responseTexts.isEmpty)
        #expect(secondTranscript.promptTexts == ["do it", Agent.continuationPrompt])
    }

    @Test
    func throwingTool_reportsErrorToModelAndContinues() async throws {
        // Given
        let model = MockLanguageModel(steps: [
            .toolCall(id: "toolu_2", name: "fail", argumentsJSON: #"{"reason": "boom"}"#),
            .text("The tool failed."),
        ])
        let terminal = MockChatTerminal(scriptedInputs: ["try it", nil])
        let agent = Agent(model: model, tools: [FailingTool()], terminal: terminal)

        // When
        try await agent.run()

        // Then
        #expect(terminal.agentMessages == ["The tool failed."])
        let toolOutputs = model.recordedTranscripts[1].toolOutputTexts
        #expect(toolOutputs.count == 1)
        #expect(toolOutputs[0].hasPrefix("Error:"))
    }

    @Test
    func unknownTool_returnsNotFoundResultWithoutExecutingAnyTool() async throws {
        // Given
        let model = MockLanguageModel(steps: [
            .toolCall(id: "toolu_9", name: "mystery", argumentsJSON: "{}"),
            .text("ok"),
        ])
        let terminal = MockChatTerminal(scriptedInputs: ["go", nil])
        let agent = Agent(model: model, tools: [], terminal: terminal)

        // When
        try await agent.run()

        // Then
        #expect(terminal.toolInvocations.isEmpty)
        #expect(model.recordedTranscripts[1].toolOutputTexts == ["Tool not found: mystery"])
        #expect(terminal.agentMessages == ["ok"])
    }
}

// MARK: - Test tools

/// Echoes the given text back, uppercased.
private struct EchoTool: Tool {
    let name = "echo"
    let description = "Echoes the given text back, uppercased."

    @Generable
    struct Arguments {
        @Guide(description: "Text to echo")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        arguments.text.uppercased()
    }
}

/// Always throws, to test that tool errors are reported back to the model.
private struct FailingTool: Tool {
    let name = "fail"
    let description = "Always fails with the given reason."

    @Generable
    struct Arguments {
        @Guide(description: "Reason for the failure")
        var reason: String
    }

    struct Failure: Error {
        let reason: String
    }

    func call(arguments: Arguments) async throws -> String {
        throw Failure(reason: arguments.reason)
    }
}
