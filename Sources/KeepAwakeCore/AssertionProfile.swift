import Foundation

public struct AssertionProfile: Equatable, Sendable {
    public var preventDisplaySleep: Bool
    public var preventIdleSystemSleep: Bool
    public var preventSystemSleep: Bool
    public var preventDiskIdle: Bool
    public var declareUserActivity: Bool

    public init(
        preventDisplaySleep: Bool,
        preventIdleSystemSleep: Bool,
        preventSystemSleep: Bool,
        preventDiskIdle: Bool,
        declareUserActivity: Bool
    ) {
        self.preventDisplaySleep = preventDisplaySleep
        self.preventIdleSystemSleep = preventIdleSystemSleep
        self.preventSystemSleep = preventSystemSleep
        self.preventDiskIdle = preventDiskIdle
        self.declareUserActivity = declareUserActivity
    }

    public static let standard = AssertionProfile(
        preventDisplaySleep: true,
        preventIdleSystemSleep: true,
        preventSystemSleep: false,
        preventDiskIdle: false,
        declareUserActivity: false
    )

    public static let empty = AssertionProfile(
        preventDisplaySleep: false,
        preventIdleSystemSleep: false,
        preventSystemSleep: false,
        preventDiskIdle: false,
        declareUserActivity: false
    )

    public var holdsAssertion: Bool {
        preventDisplaySleep || preventIdleSystemSleep || preventSystemSleep || preventDiskIdle
    }

    public var names: [String] {
        var items: [String] = []
        if preventDisplaySleep { items.append("display") }
        if preventIdleSystemSleep { items.append("idle system") }
        if preventSystemSleep { items.append("system") }
        if preventDiskIdle { items.append("disk") }
        if declareUserActivity { items.append("user activity") }
        return items
    }

    public var summary: String {
        let items = names
        return items.isEmpty ? "none" : items.joined(separator: ", ")
    }
}

public enum AssertionBackend: String, Equatable, Sendable, CaseIterable {
    case auto
    case iokit
    case caffeinate

    public init(parsing raw: String) throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let backend = AssertionBackend(rawValue: key) else {
            throw KeepAwakeError.invalidArgument(
                "Unknown backend \"\(raw)\". Use auto, iokit, or caffeinate."
            )
        }
        self = backend
    }
}

public enum HoldMode: Equatable, Sendable {
    case indefinite
    case duration(TimeInterval)
    case until(Date)
    case whileApp(String)
    case whileProcess(String)
    case whilePID(Int32)
    case schedule(WeeklySchedule)

    public var keepsAliveByDefault: Bool {
        switch self {
        case .indefinite, .whileApp, .whileProcess, .whilePID, .schedule:
            return true
        case .duration, .until:
            return false
        }
    }
}

public enum SessionAction: Equatable, Sendable {
    case hold(until: Date?)
    case wait(until: Date)
    case finished
}

public func sessionAction(
    mode: HoldMode,
    now: Date,
    startedAt: Date,
    calendar: Calendar
) -> SessionAction {
    switch mode {
    case .indefinite:
        return .hold(until: nil)
    case .duration(let interval):
        let end = startedAt.addingTimeInterval(interval)
        if now >= end { return .finished }
        return .hold(until: end)
    case .until(let date):
        if now >= date { return .finished }
        return .hold(until: date)
    case .whileApp, .whileProcess, .whilePID:
        return .hold(until: nil)
    case .schedule(let schedule):
        guard !schedule.windows.isEmpty else { return .finished }
        if schedule.contains(now, calendar: calendar) {
            return .hold(until: schedule.nextTransition(after: now, calendar: calendar))
        }
        if let next = schedule.nextTransition(after: now, calendar: calendar) {
            return .wait(until: next)
        }
        return .finished
    }
}
