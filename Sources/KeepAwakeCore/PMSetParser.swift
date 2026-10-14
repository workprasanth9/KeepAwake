import Foundation

public struct AssertionRecord: Equatable, Sendable {
    public var pid: Int
    public var processName: String
    public var age: String
    public var type: String
    public var name: String

    public init(pid: Int, processName: String, age: String, type: String, name: String) {
        self.pid = pid
        self.processName = processName
        self.age = age
        self.type = type
        self.name = name
    }

    public var ownedByKeepAwake: Bool {
        processName.caseInsensitiveCompare("keepawake") == .orderedSame
            || name.localizedCaseInsensitiveContains("keepawake")
    }
}

public struct PMSetReport: Equatable, Sendable {
    public var counts: [String: Int]
    public var assertions: [AssertionRecord]
    public var rawError: String?

    public init(counts: [String: Int], assertions: [AssertionRecord], rawError: String? = nil) {
        self.counts = counts
        self.assertions = assertions
        self.rawError = rawError
    }
}

public func parsePMSetAssertions(_ text: String) -> PMSetReport {
    var counts: [String: Int] = [:]
    var assertions: [AssertionRecord] = []
    var inSummary = false
    let assertionPattern = #"pid\s+(\d+)\(([^)]*)\):\s+\[[^\]]+\]\s+(\S+)\s+(\S+)\s+named:\s+"(.*)"#
    let assertionExpression = try? NSRegularExpression(pattern: assertionPattern, options: [])
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        if line.contains("Assertion status system-wide:") {
            inSummary = true
            continue
        }
        if line.contains("Listed by owning process:") {
            inSummary = false
            continue
        }
        if inSummary {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if parts.count == 2, let count = Int(parts[1]), parts[0].allSatisfy({ $0.isLetter || $0.isNumber }) {
                counts[parts[0]] = count
            }
            continue
        }
        guard let expression = assertionExpression else { continue }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = expression.firstMatch(in: line, options: [], range: range) else { continue }
        func group(_ index: Int) -> String {
            let matchRange = match.range(at: index)
            guard let swiftRange = Range(matchRange, in: line) else { return "" }
            return String(line[swiftRange])
        }
        guard let pid = Int(group(1)) else { continue }
        assertions.append(
            AssertionRecord(
                pid: pid,
                processName: group(2),
                age: group(3),
                type: group(4),
                name: group(5)
            )
        )
    }
    return PMSetReport(counts: counts, assertions: assertions)
}

public struct LaunchdPrintInfo: Equatable, Sendable {
    public var state: String?
    public var pid: Int?

    public init(state: String?, pid: Int?) {
        self.state = state
        self.pid = pid
    }
}

public func parseLaunchctlPrint(_ text: String) -> LaunchdPrintInfo {
    var state: String?
    var pid: Int?
    let stateExpression = try? NSRegularExpression(pattern: #"^\s*state\s*=\s*([A-Za-z0-9_-]+)\s*$"#, options: [.anchorsMatchLines])
    let pidExpression = try? NSRegularExpression(pattern: #"^\s*pid\s*=\s*([0-9]+)\s*$"#, options: [.anchorsMatchLines])
    let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
    if let match = stateExpression?.firstMatch(in: text, options: [], range: fullRange),
       let range = Range(match.range(at: 1), in: text) {
        state = String(text[range])
    }
    if let match = pidExpression?.firstMatch(in: text, options: [], range: fullRange),
       let range = Range(match.range(at: 1), in: text) {
        pid = Int(text[range])
    }
    return LaunchdPrintInfo(state: state, pid: pid)
}
