import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct JobSnapshot: Equatable, Sendable {
    public var scope: String
    public var label: String
    public var plistPath: String
    public var domain: String
    public var loaded: Bool
    public var state: String?
    public var pid: Int?
    public var programArguments: [String]

    public init(
        scope: String,
        label: String,
        plistPath: String,
        domain: String,
        loaded: Bool,
        state: String?,
        pid: Int?,
        programArguments: [String]
    ) {
        self.scope = scope
        self.label = label
        self.plistPath = plistPath
        self.domain = domain
        self.loaded = loaded
        self.state = state
        self.pid = pid
        self.programArguments = programArguments
    }
}

public struct StatusReport: Equatable, Sendable {
    public var jobs: [JobSnapshot]
    public var sessions: [SessionState]
    public var power: PMSetReport

    public init(jobs: [JobSnapshot], sessions: [SessionState], power: PMSetReport) {
        self.jobs = jobs
        self.sessions = sessions
        self.power = power
    }
}

public struct StatusQuery {
    public var plistDirectories: [URL]
    public var sessionDirectories: [URL]
    public var domain: (URL) -> String
    public var scopeName: (URL) -> String
    public var run: (String, [String]) -> CommandResult
    public var label: String?
    public var keepAwakeOnly: Bool
    public var removeStaleSessions: Bool

    public init(
        plistDirectories: [URL],
        sessionDirectories: [URL],
        domain: @escaping (URL) -> String,
        scopeName: @escaping (URL) -> String,
        run: @escaping (String, [String]) -> CommandResult,
        label: String?,
        keepAwakeOnly: Bool,
        removeStaleSessions: Bool
    ) {
        self.plistDirectories = plistDirectories
        self.sessionDirectories = sessionDirectories
        self.domain = domain
        self.scopeName = scopeName
        self.run = run
        self.label = label
        self.keepAwakeOnly = keepAwakeOnly
        self.removeStaleSessions = removeStaleSessions
    }
}

public func collectStatus(_ query: StatusQuery) -> StatusReport {
    let jobs = discoverJobs(query)
    let sessions = SessionStore.loadAll(
        directories: query.sessionDirectories,
        removeStale: query.removeStaleSessions
    )
    let pmset = query.run("/usr/bin/pmset", ["-g", "assertions"])
    var power = parsePMSetAssertions(pmset.stdout)
    if !pmset.succeeded {
        let detail = pmset.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        power.rawError = detail.isEmpty ? "pmset exited with status \(pmset.status)." : detail
    }
    if query.keepAwakeOnly {
        power.assertions = power.assertions.filter(\.ownedByKeepAwake)
    }
    return StatusReport(jobs: jobs, sessions: sessions, power: power)
}

public func statusLines(_ report: StatusReport, calendar: Calendar = .current) -> [String] {
    var lines: [String] = []
    if report.jobs.isEmpty {
        lines.append("Launchd jobs: none")
    } else {
        lines.append("Launchd jobs:")
        for job in report.jobs {
            lines.append("\(job.scope) \(job.label)")
            lines.append("  Plist: \(job.plistPath)")
            lines.append("  Domain: \(job.domain)")
            if job.loaded {
                let state = job.state ?? "loaded"
                if let pid = job.pid {
                    lines.append("  Launchd: \(state) (pid \(pid))")
                } else {
                    lines.append("  Launchd: \(state)")
                }
            } else {
                lines.append("  Launchd: not loaded")
            }
            if job.programArguments.count > 1 {
                lines.append("  Arguments: \(job.programArguments.dropFirst().joined(separator: " "))")
            }
        }
    }
    lines.append("Sessions:")
    if report.sessions.isEmpty {
        lines.append("  none")
    } else {
        for session in report.sessions {
            var detail = "  pid \(session.pid): \(session.summary), \(session.profile.joined(separator: ", ")), backend \(session.backend)"
            detail += ", started \(formatTimestamp(session.startedAt, calendar: calendar))"
            if let endsAt = session.endsAt {
                detail += ", ends \(formatTimestamp(endsAt, calendar: calendar))"
            }
            lines.append(detail)
        }
    }
    lines.append("Power assertions:")
    if let error = report.power.rawError {
        lines.append("  pmset failed: \(error)")
    }
    let interesting = [
        "PreventUserIdleDisplaySleep",
        "PreventUserIdleSystemSleep",
        "PreventSystemSleep",
        "PreventDiskIdle",
    ]
    var names = interesting
    for name in report.power.counts.keys.sorted() where !interesting.contains(name) && (report.power.counts[name] ?? 0) > 0 {
        names.append(name)
    }
    if report.power.counts.isEmpty, report.power.rawError == nil {
        lines.append("  pmset did not report assertion counts.")
    } else {
        for name in names {
            lines.append("  \(name): \(report.power.counts[name] ?? 0)")
        }
    }
    if report.power.assertions.isEmpty {
        lines.append("  No matching assertions are listed.")
    } else {
        for assertion in report.power.assertions {
            lines.append(
                "  pid \(assertion.pid) (\(assertion.processName)): \(assertion.type) named \"\(assertion.name)\" for \(assertion.age)"
            )
        }
    }
    return lines
}

public func statusJSON(_ report: StatusReport) -> [String: Any] {
    let jobs: [[String: Any]] = report.jobs.map { job in
        [
            "scope": job.scope,
            "label": job.label,
            "plist": job.plistPath,
            "domain": job.domain,
            "loaded": job.loaded,
            "state": job.state ?? NSNull(),
            "pid": job.pid ?? NSNull(),
            "arguments": job.programArguments,
        ]
    }
    let sessions: [[String: Any]] = report.sessions.map { session in
        [
            "pid": Int(session.pid),
            "mode": session.mode,
            "summary": session.summary,
            "reason": session.reason,
            "profile": session.profile,
            "backend": session.backend,
            "startedAt": formatISO8601(session.startedAt),
            "endsAt": session.endsAt.map(formatISO8601) ?? NSNull(),
        ]
    }
    let assertions: [[String: Any]] = report.power.assertions.map { assertion in
        [
            "pid": assertion.pid,
            "process": assertion.processName,
            "age": assertion.age,
            "type": assertion.type,
            "name": assertion.name,
            "keepAwake": assertion.ownedByKeepAwake,
        ]
    }
    return [
        "jobs": jobs,
        "sessions": sessions,
        "counts": report.power.counts,
        "assertions": assertions,
        "pmsetError": report.power.rawError ?? NSNull(),
    ]
}

public func isKeepAwakeJob(_ dictionary: [String: Any]) -> Bool {
    if let label = dictionary["Label"] as? String, label.hasPrefix("com.keepawake") {
        return true
    }
    guard let arguments = dictionary["ProgramArguments"] as? [String] else { return false }
    let binary = arguments.contains { URL(fileURLWithPath: $0).lastPathComponent == "keepawake" }
    return binary && arguments.contains("start")
}

func launchdDomain(forPlist url: URL) -> String {
    if url.path.contains("/LaunchDaemons/") {
        return "system"
    }
    let home = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    if let match = account(named: home.lastPathComponent) {
        return "gui/\(match.uid)"
    }
    return "gui/\(getuid())"
}

private func discoverJobs(_ query: StatusQuery) -> [JobSnapshot] {
    var jobs: [JobSnapshot] = []
    let fileManager = FileManager.default
    for directory in query.plistDirectories {
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            continue
        }
        for url in urls.sorted(by: { $0.path < $1.path }) where url.pathExtension == "plist" {
            guard let dictionary = try? plistDictionary(at: url) else { continue }
            let label = (dictionary["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
            if let wanted = query.label {
                guard label == wanted else { continue }
            } else if !isKeepAwakeJob(dictionary) {
                continue
            }
            let domain = query.domain(url)
            let printed = query.run("/bin/launchctl", ["print", "\(domain)/\(label)"])
            let info = parseLaunchctlPrint(printed.stdout)
            let arguments = dictionary["ProgramArguments"] as? [String] ?? []
            jobs.append(
                JobSnapshot(
                    scope: query.scopeName(url),
                    label: label,
                    plistPath: url.path,
                    domain: domain,
                    loaded: printed.succeeded,
                    state: info.state,
                    pid: info.pid,
                    programArguments: arguments
                )
            )
        }
    }
    return jobs
}

public func defaultStatusQuery(label: String?, keepAwakeOnly: Bool) -> StatusQuery {
    let account = currentAccount()
    var directories = [
        account.home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true),
        URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true),
    ]
    if isRootUser() {
        let users = URL(fileURLWithPath: "/Users", isDirectory: true)
        if let homes = try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil) {
            for home in homes {
                directories.append(
                    home
                        .appendingPathComponent("Library", isDirectory: true)
                        .appendingPathComponent("LaunchAgents", isDirectory: true)
                )
            }
        }
    }
    var seen = Set<String>()
    directories = directories.filter { seen.insert($0.standardizedFileURL.path).inserted }
    let sessions = [
        SessionStore.directoryForCurrentProcess(),
        account.home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("KeepAwake", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true),
        URL(fileURLWithPath: "/Library/Application Support/KeepAwake/sessions", isDirectory: true),
    ]
    return StatusQuery(
        plistDirectories: directories,
        sessionDirectories: sessions,
        domain: { url in
            launchdDomain(forPlist: url)
        },
        scopeName: { url in
            url.path.contains("/LaunchDaemons/") ? "LaunchDaemon" : "LaunchAgent"
        },
        run: { executable, arguments in
            CommandRunner.run(executable, arguments)
        },
        label: label,
        keepAwakeOnly: keepAwakeOnly,
        removeStaleSessions: true
    )
}
