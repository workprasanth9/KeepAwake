import Foundation

public enum RequestContext: Equatable, Sendable {
    case start
    case install
}

public struct StartInput: Equatable, Sendable {
    public var indefinite: Bool
    public var duration: String?
    public var until: String?
    public var whileApp: String?
    public var whileProcess: String?
    public var whilePID: Int32?
    public var schedule: String?
    public var display: Bool
    public var idleSystem: Bool
    public var systemSleep: Bool
    public var disk: Bool
    public var userActivity: Bool
    public var reason: String?
    public var backend: String?

    public init(
        indefinite: Bool = false,
        duration: String? = nil,
        until: String? = nil,
        whileApp: String? = nil,
        whileProcess: String? = nil,
        whilePID: Int32? = nil,
        schedule: String? = nil,
        display: Bool = false,
        idleSystem: Bool = false,
        systemSleep: Bool = false,
        disk: Bool = false,
        userActivity: Bool = false,
        reason: String? = nil,
        backend: String? = nil
    ) {
        self.indefinite = indefinite
        self.duration = duration
        self.until = until
        self.whileApp = whileApp
        self.whileProcess = whileProcess
        self.whilePID = whilePID
        self.schedule = schedule
        self.display = display
        self.idleSystem = idleSystem
        self.systemSleep = systemSleep
        self.disk = disk
        self.userActivity = userActivity
        self.reason = reason
        self.backend = backend
    }

    public var specifiedModeCount: Int {
        var count = 0
        if indefinite { count += 1 }
        if duration != nil { count += 1 }
        if until != nil { count += 1 }
        if whileApp != nil { count += 1 }
        if whileProcess != nil { count += 1 }
        if whilePID != nil { count += 1 }
        if schedule != nil { count += 1 }
        return count
    }

    public var specifiedAssertionFlags: Bool {
        display || idleSystem || systemSleep || disk
    }
}

public struct ResolvedRequest: Equatable, Sendable {
    public var mode: HoldMode
    public var profile: AssertionProfile
    public var reason: String
    public var backend: AssertionBackend
    public var summary: String
    public var modeArguments: [String]

    public init(
        mode: HoldMode,
        profile: AssertionProfile,
        reason: String,
        backend: AssertionBackend,
        summary: String,
        modeArguments: [String]
    ) {
        self.mode = mode
        self.profile = profile
        self.reason = reason
        self.backend = backend
        self.summary = summary
        self.modeArguments = modeArguments
    }

    public func launchArguments(binary: String) -> [String] {
        var arguments = [binary, "start"]
        arguments.append(contentsOf: modeArguments)
        if profile.preventDisplaySleep { arguments.append("--display") }
        if profile.preventIdleSystemSleep { arguments.append("--idle-system") }
        if profile.preventSystemSleep { arguments.append("--system") }
        if profile.preventDiskIdle { arguments.append("--disk") }
        if profile.declareUserActivity { arguments.append("--user-activity") }
        arguments.append(contentsOf: ["--reason", reason])
        arguments.append(contentsOf: ["--backend", backend.rawValue])
        return arguments
    }

    public func planLines(now: Date, calendar: Calendar) -> [String] {
        var lines = [
            "Mode: \(summary)",
            "Profile: \(profile.summary)",
            "Backend: \(backend.rawValue)",
            "Reason: \(reason)",
        ]
        switch mode {
        case .duration(let interval):
            lines.append("Ends: \(formatTimestamp(now.addingTimeInterval(interval), calendar: calendar))")
        case .until(let date):
            lines.append("Ends: \(formatTimestamp(date, calendar: calendar))")
        case .schedule(let schedule):
            let active = schedule.contains(now, calendar: calendar)
            lines.append("Schedule active now: \(active ? "yes" : "no")")
            if let next = schedule.nextTransition(after: now, calendar: calendar) {
                lines.append("Next change: \(formatTimestamp(next, calendar: calendar))")
            }
        default:
            break
        }
        let caffeinate = caffeinateArguments(for: self, now: now)
        lines.append("caffeinate: caffeinate \(caffeinate.joined(separator: " "))")
        return lines
    }

    public func planJSON(now: Date) -> [String: Any] {
        var object: [String: Any] = [
            "summary": summary,
            "profile": profile.names,
            "backend": backend.rawValue,
            "reason": reason,
            "modeArguments": modeArguments,
            "caffeinate": caffeinateArguments(for: self, now: now),
        ]
        switch mode {
        case .indefinite:
            object["mode"] = "indefinite"
        case .duration(let interval):
            object["mode"] = "duration"
            object["seconds"] = Int(interval.rounded())
            object["endsAt"] = formatISO8601(now.addingTimeInterval(interval))
        case .until(let date):
            object["mode"] = "until"
            object["endsAt"] = formatISO8601(date)
        case .whileApp(let name):
            object["mode"] = "whileApp"
            object["name"] = name
        case .whileProcess(let name):
            object["mode"] = "whileProcess"
            object["name"] = name
        case .whilePID(let pid):
            object["mode"] = "whilePID"
            object["pid"] = Int(pid)
        case .schedule(let schedule):
            object["mode"] = "schedule"
            object["schedule"] = schedule.source
        }
        return object
    }
}

public enum RequestResolver {
    public static func resolve(
        _ input: StartInput,
        config: ManagedConfig,
        now: Date,
        calendar: Calendar,
        context: RequestContext
    ) throws -> ResolvedRequest {
        if config.disabled {
            throw KeepAwakeError.policyDenied(
                "Managed preferences disable KeepAwake. Remove Disabled or set it to false in domain \(KeepAwake.preferenceDomain)."
            )
        }
        if input.specifiedModeCount > 1 {
            throw KeepAwakeError.conflictingModes
        }
        let modeSelection = try selectMode(input, config: config, now: now, calendar: calendar, context: context)
        try enforceDurationLimit(modeSelection.mode, config: config, now: now)
        let profile = try selectProfile(input, config: config)
        guard profile.holdsAssertion else {
            throw KeepAwakeError.invalidArgument(
                "Select at least one assertion type: --display, --idle-system, --system, or --disk."
            )
        }
        let reason = try selectReason(input, config: config)
        let backend = try selectBackend(input, config: config)
        return ResolvedRequest(
            mode: modeSelection.mode,
            profile: profile,
            reason: reason,
            backend: backend,
            summary: modeSelection.summary,
            modeArguments: modeSelection.arguments
        )
    }
}

private struct ModeSelection {
    var mode: HoldMode
    var summary: String
    var arguments: [String]
}

private func selectMode(
    _ input: StartInput,
    config: ManagedConfig,
    now: Date,
    calendar: Calendar,
    context: RequestContext
) throws -> ModeSelection {
    if config.enforceSchedule {
        guard let raw = config.defaultSchedule, !raw.isEmpty else {
            throw KeepAwakeError.policyDenied(
                "EnforceSchedule is true, but DefaultSchedule is empty in domain \(KeepAwake.preferenceDomain)."
            )
        }
        let schedule = try parseManagedSchedule(raw)
        if input.specifiedModeCount > 0 {
            let matches = try inputMatchesSchedule(input, schedule: schedule)
            if !matches {
                throw KeepAwakeError.policyDenied(
                    "Managed preferences lock the schedule to \(schedule.source)."
                )
            }
        }
        return ModeSelection(
            mode: .schedule(schedule),
            summary: "schedule \(schedule.source)",
            arguments: ["--schedule", schedule.source]
        )
    }

    if input.indefinite {
        return ModeSelection(mode: .indefinite, summary: "indefinite", arguments: ["--indefinite"])
    }
    if let duration = input.duration {
        let seconds = try parseDuration(duration)
        return ModeSelection(
            mode: .duration(seconds),
            summary: "duration \(duration)",
            arguments: ["--duration", duration]
        )
    }
    if let until = input.until {
        let date = try parseUntil(until, now: now, calendar: calendar)
        return ModeSelection(
            mode: .until(date),
            summary: "until \(until) (\(formatTimestamp(date, calendar: calendar)))",
            arguments: ["--until", until]
        )
    }
    if let name = input.whileApp {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KeepAwakeError.invalidArgument("--while-app needs an application name.")
        }
        return ModeSelection(
            mode: .whileApp(trimmed),
            summary: "while app \(trimmed) is running",
            arguments: ["--while-app", trimmed]
        )
    }
    if let name = input.whileProcess {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KeepAwakeError.invalidArgument("--while-process needs a process name.")
        }
        return ModeSelection(
            mode: .whileProcess(trimmed),
            summary: "while process \(trimmed) is running",
            arguments: ["--while-process", trimmed]
        )
    }
    if let pid = input.whilePID {
        guard pid > 0 else {
            throw KeepAwakeError.invalidArgument("--while-pid must be greater than zero.")
        }
        return ModeSelection(
            mode: .whilePID(pid),
            summary: "while pid \(pid) is running",
            arguments: ["--while-pid", String(pid)]
        )
    }
    if let raw = input.schedule {
        let schedule = try parseSchedule(raw)
        return ModeSelection(
            mode: .schedule(schedule),
            summary: "schedule \(schedule.source)",
            arguments: ["--schedule", schedule.source]
        )
    }
    if context == .install, let raw = config.defaultSchedule, !raw.isEmpty {
        let schedule = try parseManagedSchedule(raw)
        return ModeSelection(
            mode: .schedule(schedule),
            summary: "schedule \(schedule.source)",
            arguments: ["--schedule", schedule.source]
        )
    }
    return ModeSelection(mode: .indefinite, summary: "indefinite", arguments: ["--indefinite"])
}

private func parseManagedSchedule(_ raw: String) throws -> WeeklySchedule {
    do {
        return try parseSchedule(raw)
    } catch let error as KeepAwakeError {
        throw KeepAwakeError.policyDenied(
            "DefaultSchedule \"\(raw)\" is not valid. \(error.description)"
        )
    }
}

private func inputMatchesSchedule(_ input: StartInput, schedule: WeeklySchedule) throws -> Bool {
    guard input.specifiedModeCount == 1, let raw = input.schedule else {
        return false
    }
    let parsed = try parseSchedule(raw)
    return parsed.windows == schedule.windows
}

private func enforceDurationLimit(_ mode: HoldMode, config: ManagedConfig, now: Date) throws {
    let maximum = config.maximumDurationSeconds.map { TimeInterval($0) }
    switch mode {
    case .indefinite:
        if !config.allowIndefinite {
            throw KeepAwakeError.policyDenied("Managed preferences do not allow an indefinite hold.")
        }
        if maximum != nil {
            throw KeepAwakeError.policyDenied(
                "Managed preferences set a maximum duration of \(formatDuration(maximum ?? 0)), so an indefinite hold is not allowed."
            )
        }
    case .whileApp, .whileProcess, .whilePID:
        if !config.allowIndefinite || maximum != nil {
            throw KeepAwakeError.policyDenied(
                "Managed preferences require a bounded duration. Use --duration, --until, or --schedule."
            )
        }
    case .duration(let interval):
        if let maximum, interval > maximum {
            throw KeepAwakeError.policyDenied(
                "Requested duration \(formatDuration(interval)) is longer than the managed maximum of \(formatDuration(maximum))."
            )
        }
    case .until(let date):
        let interval = date.timeIntervalSince(now)
        if let maximum, interval > maximum {
            throw KeepAwakeError.policyDenied(
                "Requested end time is \(formatDuration(interval)) away, longer than the managed maximum of \(formatDuration(maximum))."
            )
        }
    case .schedule(let schedule):
        if let maximum {
            for window in schedule.windows where window.duration > maximum {
                throw KeepAwakeError.policyDenied(
                    "Schedule window \(describeWindow(window)) is longer than the managed maximum of \(formatDuration(maximum))."
                )
            }
        }
    }
}

private func selectProfile(_ input: StartInput, config: ManagedConfig) throws -> AssertionProfile {
    let managed = managedProfile(config)
    if input.specifiedAssertionFlags || input.userActivity {
        let requested = AssertionProfile(
            preventDisplaySleep: input.display,
            preventIdleSystemSleep: input.idleSystem,
            preventSystemSleep: input.systemSleep,
            preventDiskIdle: input.disk,
            declareUserActivity: input.userActivity
        )
        if config.lockAssertionProfile, requested != managed {
            throw KeepAwakeError.policyDenied(
                "Assertion profile is locked by managed preferences (\(managed.summary))."
            )
        }
        if config.lockAssertionProfile {
            return managed
        }
        if input.specifiedAssertionFlags {
            return requested
        }
        var combined = managed
        combined.declareUserActivity = true
        return combined
    }
    return managed
}

private func managedProfile(_ config: ManagedConfig) -> AssertionProfile {
    var profile = AssertionProfile.standard
    if let value = config.preventDisplaySleep { profile.preventDisplaySleep = value }
    if let value = config.preventIdleSystemSleep { profile.preventIdleSystemSleep = value }
    if let value = config.preventSystemSleep { profile.preventSystemSleep = value }
    if let value = config.preventDiskIdle { profile.preventDiskIdle = value }
    if let value = config.declareUserActivity { profile.declareUserActivity = value }
    return profile
}

private func selectReason(_ input: StartInput, config: ManagedConfig) throws -> String {
    let managed = config.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = (managed?.isEmpty == false ? managed! : KeepAwake.defaultReason)
    guard let requested = input.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !requested.isEmpty else {
        return fallback
    }
    if config.lockReason, requested != fallback {
        throw KeepAwakeError.policyDenied("Assertion reason is locked by managed preferences.")
    }
    return requested
}

private func selectBackend(_ input: StartInput, config: ManagedConfig) throws -> AssertionBackend {
    let managed: AssertionBackend
    if let raw = config.backend, !raw.isEmpty {
        do {
            managed = try AssertionBackend(parsing: raw)
        } catch {
            throw KeepAwakeError.policyDenied(
                "Managed preferences set Backend to \"\(raw)\", which is not auto, iokit, or caffeinate."
            )
        }
    } else {
        managed = .auto
    }
    guard let raw = input.backend, !raw.isEmpty else {
        return managed
    }
    let requested = try AssertionBackend(parsing: raw)
    if config.lockBackend, requested != managed {
        throw KeepAwakeError.policyDenied(
            "Assertion backend is locked to \(managed.rawValue) by managed preferences."
        )
    }
    return requested
}
