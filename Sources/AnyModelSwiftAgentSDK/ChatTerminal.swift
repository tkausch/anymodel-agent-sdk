import Foundation
import AnyLanguageModel

// MARK: - ChatTerminalProtocol

/// Abstracts the terminal I/O `Agent` depends on, so tests can substitute a
/// scripted implementation instead of driving real stdio.
protocol ChatTerminalProtocol: Sendable {
    func intro()
    func readUserInput() -> String?
    func agent(_ text: String)
    func tool(name: String, arguments: GeneratedContent)
}

// MARK: - ChatTerminal

/// Handles all terminal I/O for the conversation UI.
struct ChatTerminal: ChatTerminalProtocol {

    func intro() {
        print("Chat with the agent (use 'ctrl-c' to quit)")
    }

    /// Prints the coloured "You:" prompt and reads the next line of user input.
    /// Returns `nil` at EOF.
    func readUserInput() -> String? {
        print("\(ansi("You", code: 94)): ", terminator: "")
        return readLine()
    }

    /// Prints a coloured "Agent:" reply line.
    func agent(_ text: String) {
        print("\(ansi("Agent", code: 93)): \(text)")
    }

    /// Prints a coloured "tool:" invocation line.
    func tool(name: String, arguments: GeneratedContent) {
        print("\(ansi("tool", code: 92)): \(name)(\(arguments.argumentList))")
    }

    private func ansi(_ s: String, code: Int) -> String {
        "\u{001B}[\(code)m\(s)\u{001B}[0m"
    }
}

// MARK: - GeneratedContent display

extension GeneratedContent {
    /// Tool arguments formatted as `key: value, …`, as shown in the terminal and logs.
    var argumentList: String {
        guard case .structure(let properties, let orderedKeys) = kind else { return displayString }
        return orderedKeys.compactMap { key in
            properties[key].map { "\(key): \($0.displayString)" }
        }.joined(separator: ", ")
    }

    private var displayString: String {
        switch kind {
        case .string(let s): return s
        case .null:          return "null"
        default:             return jsonString
        }
    }
}
