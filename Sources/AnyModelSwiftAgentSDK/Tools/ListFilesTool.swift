import Foundation
import AnyLanguageModel

/// Lists files and directories at a given path.
///
/// Equivalent to the Go `ListFilesDefinition` tool.
public struct ListFilesTool: Tool {

    public let name = "list_files"

    public let description = """
        List files and directories at a given path. \
        If no path is provided, lists files in the current directory.
        """

    @Generable
    public struct Arguments {
        @Guide(description: "Optional relative path to list files from. Defaults to current directory if not provided.")
        public var path: String?
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> String {
        var directory: String = "."
        if let path = arguments.path, !path.isEmpty {
            directory = path
        }

        let data = try JSONEncoder().encode(try listFiles(in: directory))
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Recursively lists `directory`, marking subdirectories with a trailing `/`.
    /// Synchronous because `NSDirectoryEnumerator` can't be iterated from async code.
    private func listFiles(in directory: String) throws -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            throw ToolError.executionFailed("Unable to list files at \(directory)")
        }

        var files: [String] = []
        for item in enumerator {
            guard let relativePath = item as? String else { continue }

            var isDirectory: ObjCBool = false
            let fullPath = (directory as NSString).appendingPathComponent(relativePath)
            fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory)

            files.append(isDirectory.boolValue ? relativePath + "/" : relativePath)
        }
        return files
    }
}
