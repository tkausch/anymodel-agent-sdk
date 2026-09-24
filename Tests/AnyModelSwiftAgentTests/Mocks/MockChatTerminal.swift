@testable import AnyModelSwiftAgentSDK
import AnyLanguageModel

/// A scripted `ChatTerminalProtocol` implementation used to drive `Agent` in
/// tests. Feeds pre-scripted user input and records everything the agent
/// prints, instead of touching real stdio.
final class MockChatTerminal: ChatTerminalProtocol, @unchecked Sendable {

    private(set) var introCallCount = 0
    private(set) var readInputCallCount = 0
    private(set) var agentMessages: [String] = []
    private(set) var toolInvocations: [(name: String, arguments: GeneratedContent)] = []

    private var scriptedInputs: [String?]

    /// - Parameter scriptedInputs: Values returned by successive calls to
    ///   `readUserInput()`, in order. Once exhausted, `nil` (EOF) is returned.
    init(scriptedInputs: [String?]) {
        self.scriptedInputs = scriptedInputs
    }

    func intro() {
        introCallCount += 1
    }

    func readUserInput() -> String? {
        readInputCallCount += 1
        guard !scriptedInputs.isEmpty else { return nil }
        return scriptedInputs.removeFirst()
    }

    func agent(_ text: String) {
        agentMessages.append(text)
    }

    func tool(name: String, arguments: GeneratedContent) {
        toolInvocations.append((name: name, arguments: arguments))
    }
}
