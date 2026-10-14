import Foundation

public struct CommandResult: Equatable, Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { status == 0 }
}

public enum CommandRunner {
    public static func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("keepawake-out-\(UUID().uuidString)")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("keepawake-err-\(UUID().uuidString)")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        do {
            let outputHandle = try FileHandle(forWritingTo: outputURL)
            let errorHandle = try FileHandle(forWritingTo: errorURL)
            process.standardOutput = outputHandle
            process.standardError = errorHandle
            try process.run()
            process.waitUntilExit()
            try outputHandle.close()
            try errorHandle.close()
            let stdout = String(decoding: (try? Data(contentsOf: outputURL)) ?? Data(), as: UTF8.self)
            let stderr = String(decoding: (try? Data(contentsOf: errorURL)) ?? Data(), as: UTF8.self)
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
            return CommandResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
            return CommandResult(status: 127, stdout: "", stderr: error.localizedDescription)
        }
    }
}

public protocol LaunchctlClient {
    func run(_ arguments: [String]) -> CommandResult
}

public struct SystemLaunchctl: LaunchctlClient {
    public init() {}

    public func run(_ arguments: [String]) -> CommandResult {
        CommandRunner.run("/bin/launchctl", arguments)
    }
}
