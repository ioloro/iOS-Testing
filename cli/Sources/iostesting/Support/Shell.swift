import Foundation

struct ShellResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var isSuccess: Bool { exitCode == 0 }
}

enum ShellError: Error, CustomStringConvertible {
    case nonZeroExit(command: String, exitCode: Int32, stderr: String)

    var description: String {
        switch self {
        case .nonZeroExit(let command, let exitCode, let stderr):
            return "\(command) exited \(exitCode): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

enum Shell {
    static func run(_ executable: String, _ args: [String]) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    static func runChecked(_ executable: String, _ args: [String]) async throws -> String {
        let result = try await run(executable, args)
        guard result.isSuccess else {
            throw ShellError.nonZeroExit(
                command: ([executable] + args).joined(separator: " "),
                exitCode: result.exitCode,
                stderr: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        return result.stdout
    }

    static func stream(
        _ executable: String,
        _ args: [String],
        onLine: @Sendable @escaping (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) where !line.isEmpty {
                onLine(String(line))
            }
        }
        errHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            FileHandle.standardError.write(text.data(using: .utf8) ?? Data())
        }

        try process.run()
        process.waitUntilExit()

        outHandle.readabilityHandler = nil
        errHandle.readabilityHandler = nil

        return process.terminationStatus
    }
}
