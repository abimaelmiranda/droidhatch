import Foundation

final class DroidHatchCommandRunner: @unchecked Sendable {
    private let executable: URL

    init(executable: URL) {
        self.executable = executable
    }

    func run(arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw DroidHatchContainerError.commandFailed(
                "O comando \(executable.lastPathComponent) retornou saída inválida.")
        }
        guard process.terminationStatus == 0 else {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DroidHatchContainerError.commandFailed(
                detail.isEmpty
                    ? "O comando \(executable.lastPathComponent) falhou."
                    : detail)
        }
        return output
    }
}
