import Foundation

public struct TimeOfDay: Equatable, Sendable {
    public var minutes: Int

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    public init(minutes: Int) {
        self.minutes = minutes
    }

    public var formatted: String {
        if minutes == 1_440 {
            return "24:00"
        }
        return String(format: "%02d:%02d", hour, minute)
    }
}

public struct ScheduleWindow: Equatable, Sendable {
    public var weekdays: Set<Int>
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(weekdays: Set<Int>, start: TimeOfDay, end: TimeOfDay) {
        self.weekdays = weekdays
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        let length = end.minutes >= start.minutes
            ? end.minutes - start.minutes
            : (1_440 - start.minutes) + end.minutes
        return TimeInterval(length * 60)
    }

    public func contains(weekday: Int, minuteOfDay: Int, previousWeekday: Int) -> Bool {
        let startM = start.minutes
        let endM = end.minutes
        if endM > startM {
            return weekdays.contains(weekday) && minuteOfDay >= startM && minuteOfDay < endM
        }
        if weekdays.contains(weekday), minuteOfDay >= startM {
            return true
        }
        if weekdays.contains(previousWeekday), minuteOfDay < endM {
            return true
        }
        return false
    }
}

public struct WeeklySchedule: Equatable, Sendable {
    public var source: String
    public var windows: [ScheduleWindow]

    public init(source: String, windows: [ScheduleWindow]) {
        self.source = source
        self.windows = windows
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        activeWindow(at: date, calendar: calendar) != nil
    }

    public func activeWindow(at date: Date, calendar: Calendar) -> ScheduleWindow? {
        let weekday = calendar.component(.weekday, from: date)
        let previous = weekday == 1 ? 7 : weekday - 1
        let minuteOfDay = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return windows.first {
            $0.contains(weekday: weekday, minuteOfDay: minuteOfDay, previousWeekday: previous)
        }
    }

    public func nextTransition(after date: Date, calendar: Calendar) -> Date? {
        let inside = contains(date, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let truncated = calendar.date(from: components) else {
            return nil
        }
        guard let start = calendar.date(byAdding: .minute, value: 1, to: truncated) else {
            return nil
        }
        guard let limit = calendar.date(byAdding: .day, value: 8, to: date) else {
            return nil
        }
        var probe = start
        while probe <= limit {
            if contains(probe, calendar: calendar) != inside {
                return probe
            }
            guard let next = calendar.date(byAdding: .minute, value: 1, to: probe) else {
                return nil
            }
            probe = next
        }
        return nil
    }
}

public func parseSchedule(_ raw: String) throws -> WeeklySchedule {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw KeepAwakeError.invalidSchedule(
            "Schedule is empty. Example: Mon-Fri 09:00-17:00."
        )
    }
    let chunks = trimmed.split(separator: ";", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if chunks.contains(where: { $0.isEmpty }) {
        throw KeepAwakeError.invalidSchedule(
            "Schedule \"\(raw)\" has an empty window. Separate windows with a semicolon."
        )
    }
    let windows = try chunks.map { try parseScheduleWindow($0) }
    return WeeklySchedule(source: trimmed, windows: windows)
}

public func describeWeekdays(_ days: Set<Int>) -> String {
    let order = [2, 3, 4, 5, 6, 7, 1]
    let names = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
    return order.filter { days.contains($0) }.compactMap { names[$0] }.joined(separator: ", ")
}

public func describeWindow(_ window: ScheduleWindow) -> String {
    "\(describeWeekdays(window.weekdays)) \(window.start.formatted)-\(window.end.formatted)"
}

private func parseScheduleWindow(_ text: String) throws -> ScheduleWindow {
    let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard let timeIndex = parts.firstIndex(where: { $0.contains(":") }) else {
        throw KeepAwakeError.invalidSchedule(
            "Schedule \"\(text)\" is missing a time range such as 09:00-17:00."
        )
    }
    guard timeIndex > 0 else {
        throw KeepAwakeError.invalidSchedule(
            "Schedule \"\(text)\" is missing weekdays. Example: Mon-Fri 09:00-17:00."
        )
    }
    let days = try parseWeekdays(Array(parts[..<timeIndex]), original: text)
    let timeText = parts[timeIndex...].joined()
    let bounds = timeText.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    guard bounds.count == 2, !bounds[0].isEmpty, !bounds[1].isEmpty else {
        throw KeepAwakeError.invalidSchedule(
            "Schedule \"\(text)\" needs one start and one end, such as 09:00-17:00."
        )
    }
    let startClock = try parseScheduleClock(bounds[0], role: "start")
    let endClock = try parseScheduleClock(bounds[1], role: "end")
    if startClock.minutes == 1_440 {
        throw KeepAwakeError.invalidSchedule("A schedule window cannot start at 24:00.")
    }
    if startClock.minutes == endClock.minutes {
        throw KeepAwakeError.invalidSchedule(
            "Schedule window \"\(text)\" has the same start and end. Use a range, or 00:00-24:00 for a full day."
        )
    }
    return ScheduleWindow(weekdays: days, start: startClock, end: endClock)
}

private func parseScheduleClock(_ raw: String, role: String) throws -> TimeOfDay {
    if raw.contains(":") && raw.split(separator: ":").count > 2 {
        throw KeepAwakeError.invalidSchedule(
            "Schedule times use HH:MM. \"\(raw)\" includes seconds."
        )
    }
    let clock: ParsedClock
    do {
        clock = try parseClockToken(raw, allowEndOfDay: true)
    } catch let error as KeepAwakeError {
        throw KeepAwakeError.invalidSchedule(error.description)
    }
    if role == "start", clock.hour == 24 {
        throw KeepAwakeError.invalidSchedule("A schedule window cannot start at 24:00.")
    }
    return TimeOfDay(minutes: clock.hour * 60 + clock.minute)
}

private func parseWeekdays(_ tokens: [String], original: String) throws -> Set<Int> {
    let normalized = tokens.joined().replacingOccurrences(of: " ", with: "")
    let pieces = normalized.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    guard !pieces.isEmpty else {
        throw KeepAwakeError.invalidSchedule("Schedule \"\(original)\" is missing weekdays.")
    }
    var days = Set<Int>()
    for piece in pieces {
        let key = piece.lowercased()
        if key == "all" || key == "every" {
            days.formUnion(1...7)
            continue
        }
        let bounds = piece.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if bounds.count == 1 {
            days.insert(try weekdayNumber(bounds[0], original: original))
        } else if bounds.count == 2 {
            let start = try weekdayNumber(bounds[0], original: original)
            let end = try weekdayNumber(bounds[1], original: original)
            days.formUnion(weekdayRange(from: start, to: end))
        } else {
            throw KeepAwakeError.invalidSchedule(
                "Weekday range \"\(piece)\" in \"\(original)\" is not valid. Example: Mon-Fri."
            )
        }
    }
    return days
}

private func weekdayNumber(_ raw: String, original: String) throws -> Int {
    let names: [String: Int] = [
        "sun": 1, "sunday": 1,
        "mon": 2, "monday": 2,
        "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6,
        "sat": 7, "saturday": 7,
    ]
    guard let number = names[raw.lowercased()] else {
        throw KeepAwakeError.invalidSchedule(
            "Unknown weekday \"\(raw)\" in \"\(original)\". Use Sun, Mon, Tue, Wed, Thu, Fri, or Sat."
        )
    }
    return number
}

private func weekdayRange(from start: Int, to end: Int) -> Set<Int> {
    var days = Set<Int>()
    var cursor = start
    for _ in 0..<7 {
        days.insert(cursor)
        if cursor == end {
            break
        }
        cursor = cursor == 7 ? 1 : cursor + 1
    }
    return days
}
