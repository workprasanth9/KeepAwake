import Foundation

public func formatDuration(_ seconds: TimeInterval) -> String {
    var remaining = max(0, Int(seconds.rounded()))
    if remaining == 0 {
        return "0s"
    }
    let days = remaining / 86_400
    remaining %= 86_400
    let hours = remaining / 3_600
    remaining %= 3_600
    let minutes = remaining / 60
    let secs = remaining % 60
    var parts: [String] = []
    if days > 0 { parts.append("\(days)d") }
    if hours > 0 { parts.append("\(hours)h") }
    if minutes > 0 { parts.append("\(minutes)m") }
    if secs > 0 { parts.append("\(secs)s") }
    return parts.joined()
}

public func formatTimestamp(_ date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
    return formatter.string(from: date)
}

public func formatISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

public func posixCalendar(timeZone: TimeZone? = nil) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    if let timeZone {
        calendar.timeZone = timeZone
    }
    return calendar
}

func xmlEscape(_ string: String) -> String {
    var result = ""
    result.reserveCapacity(string.count)
    for scalar in string.unicodeScalars {
        switch scalar {
        case "&":
            result += "&amp;"
        case "<":
            result += "&lt;"
        case ">":
            result += "&gt;"
        case "\"":
            result += "&quot;"
        default:
            if scalar.value < 0x20, scalar != "\n", scalar != "\t" {
                result += String(format: "&#x%04X;", scalar.value)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
    }
    return result
}

public func absoluteFileURL(_ path: String) -> URL {
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path).standardizedFileURL
    }
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return current.appendingPathComponent(path).standardizedFileURL
}

public func currentExecutablePath() -> String {
    #if os(Linux)
    if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe") {
        return destination
    }
    #endif
    #if canImport(Darwin)
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    if size > 0 {
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        if _NSGetExecutablePath(&buffer, &size) == 0 {
            let raw = String(cString: buffer)
            return absoluteFileURL(raw).path
        }
    }
    #endif
    return absoluteFileURL(CommandLine.arguments.first ?? "keepawake").path
}

func isInteractiveStandardInput() -> Bool {
    #if canImport(Darwin) || canImport(Glibc)
    return isatty(STDIN_FILENO) == 1
    #else
    return false
    #endif
}
