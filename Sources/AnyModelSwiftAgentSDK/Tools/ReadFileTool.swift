 import Foundation
import AnyLanguageModel

/// Reads the contents of a file at a relative path.
///
/// Equivalent to the Go `ReadFileDefinition` tool.
public struct ReadFileTool: Tool {

    public let name = "read_file"

    public let description = """
        Read the contents of a given relative file path. \
        Use this when you want to see what's inside a file. \
        Do not use this with directory names.
        """

    @Generable
    public struct Arguments {
        @Guide(description: "The relative path of a file in the working directory.")
        public var path: String
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> String {
        try String(contentsOfFile: arguments.path, encoding: .utf8)
    }
}
