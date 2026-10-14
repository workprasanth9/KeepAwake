import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ProcessRecord: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    public var command: String

    public init(pid: Int32, name: String, command: String) {
        self.pid = pid
        self.name = name
        self.command = command
    }
}

public func parseProcessList(_ text: String) -> [ProcessRecord] {
    var records: [ProcessRecord] = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
        let line = String(rawLine).trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { continue }
        let parts = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count >= 2, let pid = Int32(parts[0]) else { continue }
        let name = parts[1]
        let command = parts.count == 3 ? parts[2] : parts[1]
        records.append(ProcessRecord(pid: pid, name: name, command: command))
    }
    return records
}

public func processIsRunning(named name: String, in records: [ProcessRecord]) -> Bool {
    let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return false }
    return records.contains { record in
        record.name == query || executableBase(record.command) == query
    }
}

public func appIsRunning(named name: String, in records: [ProcessRecord]) -> Bool {
    let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return false }
    let lowered = query.lowercased()
    return records.contains { record in
        if record.name.lowercased() == lowered {
            return true
        }
        if executableBase(record.command).lowercased() == lowered {
            return true
        }
        return bundleNames(in: record.command).contains { $0.lowercased() == lowered }
    }
}

public func pidExists(_ pid: Int32) -> Bool {
    if pid <= 0 { return false }
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM
}

public func liveProcessRecords() -> [ProcessRecord] {
    let result = CommandRunner.run("/bin/ps", ["-ax", "-o", "pid=", "-o", "ucomm=", "-o", "command="])
    guard result.succeeded else { return [] }
    return parseProcessList(result.stdout)
}

public func terminateKeepAwakeProcess(pid: Int32) -> String {
    guard pidExists(pid) else {
        return "pid \(pid) is not running"
    }
    guard let command = processCommand(pid: pid) else {
        return "did not signal pid \(pid) because its command could not be verified"
    }
    guard command.contains("keepawake") else {
        return "did not signal pid \(pid) because it is \(command)"
    }
    if kill(pid, SIGTERM) == 0 {
        return "sent SIGTERM to pid \(pid)"
    }
    return "could not signal pid \(pid) (errno \(errno))"
}

public func processCommand(pid: Int32) -> String? {
    #if os(Linux)
    guard let data = FileManager.default.contents(atPath: "/proc/\(pid)/cmdline") else { return nil }
    let replaced = data.map { $0 == 0 ? UInt8(ascii: " ") : $0 }
    let text = String(decoding: replaced, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
    #else
    let result = CommandRunner.run("/bin/ps", ["-p", String(pid), "-o", "command="])
    guard result.succeeded else { return nil }
    let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
    #endif
}

private func executableBase(_ command: String) -> String {
    let token = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? command
    return URL(fileURLWithPath: token).lastPathComponent
}

private func bundleNames(in command: String) -> [String] {
    let pattern = #"([^/]+)\.app(?:/|$)"#
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return []
    }
    let range = NSRange(command.startIndex..<command.endIndex, in: command)
    return expression.matches(in: command, options: [], range: range).compactMap { match in
        guard let swiftRange = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[swiftRange])
    }
}
