import Foundation

struct ParsedClock {
    var hour: Int
    var minute: Int
    var second: Int
}

func parseClockToken(_ raw: String, allowEndOfDay: Bool) throws -> ParsedClock {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let pattern = #"^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap]m)?$"#
    let expression = try NSRegularExpression(pattern: pattern, options: [])
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = expression.firstMatch(in: text, options: [], range: range) else {
        throw KeepAwakeError.invalidTime(
            "Invalid time \"\(raw)\". Use 24-hour HH:MM, or 12-hour times such as 5:30pm."
        )
    }
    func capture(_ index: Int) -> String? {
        let matchRange = match.range(at: index)
        guard matchRange.location != NSNotFound, let swiftRange = Range(matchRange, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }
    guard let hourText = capture(1), let minuteText = capture(2),
          var hour = Int(hourText), let minute = Int(minuteText) else {
        throw KeepAwakeError.invalidTime("Invalid time \"\(raw)\".")
    }
    let second = Int(capture(3) ?? "0") ?? 0
    let ampm = capture(4)
    guard (0...59).contains(minute), (0...59).contains(second) else {
        throw KeepAwakeError.invalidTime("Invalid time \"\(raw)\". Minutes and seconds must be 00 through 59.")
    }
    if let ampm {
        guard (1...12).contains(hour) else {
            throw KeepAwakeError.invalidTime("Invalid time \"\(raw)\". Use an hour from 1 to 12 with am or pm.")
        }
        if ampm == "am" {
            if hour == 12 { hour = 0 }
        } else if hour != 12 {
            hour += 12
        }
    } else if allowEndOfDay, hour == 24, minute == 0, second == 0 {
        return ParsedClock(hour: 24, minute: 0, second: 0)
    } else if !(0...23).contains(hour) {
        throw KeepAwakeError.invalidTime("Invalid time \"\(raw)\". Hours must be 00 through 23.")
    }
    return ParsedClock(hour: hour, minute: minute, second: second)
}

public func parseUntil(_ raw: String, now: Date, calendar: Calendar) throws -> Date {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
        throw KeepAwakeError.invalidTime("Until time is empty. Use 17:30, 5:30pm, or 2026-10-14T18:00.")
    }
    if let absolute = parseAbsoluteDate(text, calendar: calendar) {
        guard absolute > now else {
            throw KeepAwakeError.invalidTime(
                "That time is in the past (\(formatTimestamp(absolute, calendar: calendar)))."
            )
        }
        return absolute
    }
    let clock = try parseClockToken(text, allowEndOfDay: false)
    guard let today = calendar.date(
        bySettingHour: clock.hour,
        minute: clock.minute,
        second: clock.second,
        of: now
    ) else {
        throw KeepAwakeError.invalidTime(
            "That local time does not exist today. Check the time zone and daylight saving transition."
        )
    }
    if today > now {
        return today
    }
    guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
        throw KeepAwakeError.invalidTime("Could not roll \"\(raw)\" forward to the next day.")
    }
    return tomorrow
}

private func parseAbsoluteDate(_ text: String, calendar: Calendar) -> Date? {
    if text.contains("T") || text.hasSuffix("Z") || text.contains("+") {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) {
            return date
        }
    }
    let formats = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
    ]
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in formats {
        formatter.dateFormat = format
        if let date = formatter.date(from: text) {
            return date
        }
    }
    return nil
}
