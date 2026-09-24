import Foundation
import OSLog
import AnyLanguageModel

/// Unified-logging channel for tool activity. Stream it with:
/// `log stream --level info --predicate 'subsystem == "AnyModelSwiftAgentSDK"'`
let toolLogger = Logger(subsystem: "AnyModelSwiftAgentSDK", category: "tools")

// MARK: - AgentTool

/// Wraps a tool for use by `Agent`: echoes every call to the terminal, logs it
/// (arguments, duration, result size or error) to `toolLogger`, and returns
/// errors to the model as the tool's output instead of aborting the response.
///
/// Doing this in the tool rather than in a `ToolExecutionDelegate` works for every
/// provider, including those that don't call the delegate (e.g. Apple Foundation Models).
/// `LanguageModelSession` would otherwise rethrow tool errors as `ToolCallError`,
/// ending the turn; reporting them back lets the model recover — for example by
/// retrying `geocode` with a more specific address.
struct AgentTool<Base: Tool>: Tool {
    let base: Base
    let terminal: any ChatTerminalProtocol

    var name: String { base.name }
    var description: String { base.description }
    var parameters: GenerationSchema { base.parameters }
    var includesSchemaInInstructions: Bool { base.includesSchemaInInstructions }

    func call(arguments: Base.Arguments) async throws -> String {
        let content = (arguments as? any ConvertibleToGeneratedContent)?.generatedContent
            ?? GeneratedContent(String(describing: arguments))
        terminal.tool(name: name, arguments: content)
        let call = "\(name)(\(content.argumentList))"
        toolLogger.info("Calling \(call, privacy: .public)")

        let clock = ContinuousClock()
        let start = clock.now
        do {
            let output = try await base.call(arguments: arguments)
            let result = (output as? String) ?? output.promptRepresentation.description
            toolLogger.info(
                "\(call, privacy: .public) succeeded in \(clock.now - start, privacy: .public), returned \(result.count) characters"
            )
            return result
        } catch {
            toolLogger.error(
                "\(call, privacy: .public) failed after \(clock.now - start, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return "Error: \(error.localizedDescription)"
        }
    }
}

/// Wraps any tool in an `AgentTool` that reports to `terminal`.
func agentTool(_ tool: any Tool, terminal: any ChatTerminalProtocol) -> any Tool {
    func open(_ tool: some Tool) -> any Tool { AgentTool(base: tool, terminal: terminal) }
    return open(tool)
}

// MARK: - ToolError

/// Errors a tool function can throw.
public enum ToolError: Error, LocalizedError {
    /// The arguments were missing a required value or had an unexpected type.
    case invalidInput
    /// The tool could not complete its work.
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput:                return "invalid input"
        case .executionFailed(let reason): return reason
        }
    }
}
