import ArgumentParser
import Foundation
import KeepAwakeCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct KeepAwakeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keepawake",
        abstract: "Keep a Mac awake with IOKit power assertions.",
        discussion: """
        KeepAwake holds power assertions so a Mac does not idle sleep. \
        Install a LaunchAgent or LaunchDaemon when the hold should come back after login or reboot. \
        Managed preferences in the \(KeepAwake.preferenceDomain) domain can cap duration and lock a weekly schedule.
        """,
        version: KeepAwake.version,
        subcommands: [
            Start.self,
            Stop.self,
            Resume.self,
            Status.self,
            Install.self,
            Uninstall.self,
            ScheduleCommand.self,
            Config.self,
        ]
    )
}

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Write machine readable JSON to stdout.")
    var json = false

    @Flag(name: .long, help: "Suppress informational messages.")
    var quiet = false

    @Option(name: .long, help: "Extra preferences plist. Managed preferences still override this file.")
    var config: String?
}

struct AssertionOptions: ParsableArguments {
    @Flag(name: .long, help: "Hold until interrupted. This is the default for start when no other mode is set.")
    var indefinite = false

    @Option(name: .long, help: "Hold for this long. Examples: 45m, 2h, 90s, 1h30m. A bare number is seconds.")
    var duration: String?

    @Option(name: .long, help: "Hold until this time. Examples: 17:30, 5:30pm, 2026-10-14T18:00.")
    var until: String?

    @Option(name: .customLong("while-app"), help: "Hold while an application with this name is running. Example: zoom.us.")
    var whileApp: String?

    @Option(name: .customLong("while-process"), help: "Hold while a process with this exact name is running.")
    var whileProcess: String?

    @Option(name: .customLong("while-pid"), help: "Hold while this process id is alive.")
    var whilePID: Int?

    @Option(name: .long, help: "Weekly window. Example: \"Mon-Fri 09:00-17:00\". Separate extra windows with a semicolon.")
    var schedule: String?

    @Flag(name: [.customShort("d"), .customLong("display")], help: "Prevent idle display sleep.")
    var display = false

    @Flag(name: [.customShort("i"), .customLong("idle-system")], help: "Prevent idle system sleep.")
    var idleSystem = false

    @Flag(name: [.customShort("s"), .customLong("system")], help: "Prevent system sleep on a power adapter. Closing the lid can still sleep a laptop.")
    var systemSleep = false

    @Flag(name: [.customShort("m"), .customLong("disk")], help: "Prevent disk idle sleep.")
    var disk = false

    @Flag(name: [.customShort("u"), .customLong("user-activity")], help: "Declare user activity so idle timers stay reset.")
    var userActivity = false

    @Option(name: .long, help: "Reason stored with the assertion. Visible in pmset and Activity Monitor.")
    var reason: String?

    @Option(name: .long, help: "Assertion backend: auto, iokit, or caffeinate. auto uses IOKit, then caffeinate.")
    var backend: String?

    @Flag(name: .customLong("dry-run"), help: "Print the plan and do not create an assertion or change launchd.")
    var dryRun = false

    func validate() throws {
        if makeInput().specifiedModeCount > 1 {
            throw ValidationError("Choose only one of --indefinite, --duration, --until, --while-app, --while-process, --while-pid, or --schedule.")
        }
        if let whilePID {
            guard whilePID > 0, Int32(exactly: whilePID) != nil else {
                throw ValidationError("--while-pid must be a positive process id.")
            }
        }
        if let backend {
            do {
                _ = try AssertionBackend(parsing: backend)
            } catch let error as KeepAwakeError {
                throw ValidationError(error.description)
            }
        }
    }

    func makeInput() -> StartInput {
        StartInput(
            indefinite: indefinite,
            duration: duration,
            until: until,
            whileApp: whileApp,
            whileProcess: whileProcess,
            whilePID: whilePID.flatMap { Int32(exactly: $0) },
            schedule: schedule,
            display: display,
            idleSystem: idleSystem,
            systemSleep: systemSleep,
            disk: disk,
            userActivity: userActivity,
            reason: reason,
            backend: backend
        )
    }
}

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Hold a power assertion until the requested condition ends."
    )

    @OptionGroup var global: GlobalOptions
    @OptionGroup var assertion: AssertionOptions

    func run() throws {
        try runCommand {
            let loaded = try loadConfiguration(global)
            let request = try RequestResolver.resolve(
                assertion.makeInput(),
                config: loaded.config,
                now: Date(),
                calendar: .current,
                context: .start
            )
            if global.json || assertion.dryRun {
                var object = request.planJSON(now: Date())
                object["dryRun"] = assertion.dryRun
                if global.json {
                    try emitJSON(object)
                }
            }
            if assertion.dryRun {
                if !global.json {
                    print("Dry run. No assertion was created.")
                    for line in request.planLines(now: Date(), calendar: .current) {
                        print(line)
                    }
                }
                return
            }
            let session = PowerSession(installSignalHandlers: true, log: global.quiet ? { _ in } : { message in
                fputs(message + "\n", stderr)
            })
            try session.run(request)
        }
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop KeepAwake sessions and unload launchd jobs without deleting their plists."
    )

    @OptionGroup var global: GlobalOptions
    @Flag(name: .long, help: "Only stop per-user LaunchAgents.")
    var agent = false
    @Flag(name: .long, help: "Only stop system LaunchDaemons. Requires root when a daemon is installed.")
    var daemon = false
    @Option(name: .long, help: "Only stop this launchd label.")
    var label: String?
    @Flag(name: .customLong("dry-run"), help: "Print the actions without signaling processes or changing launchd.")
    var dryRun = false

    func run() throws {
        try runCommand {
            if agent, daemon {
                throw KeepAwakeError.invalidArgument("Choose either --agent or --daemon.")
            }
            let sessions = targetedSessions()
            let jobs = try targetedJobs(agent: agent, daemon: daemon, label: label)
            if sessions.isEmpty, jobs.isEmpty {
                print("No KeepAwake session or launchd job was running.")
                return
            }
            var actions: [String] = []
            for session in sessions {
                if dryRun {
                    actions.append("would signal pid \(session.pid)")
                } else {
                    actions.append(terminateKeepAwakeProcess(pid: session.pid))
                }
            }
            let installer = LaunchdInstaller(launchctl: SystemLaunchctl(), adjustOwnership: false)
            for job in jobs {
                if dryRun {
                    actions.append("would bootout \(job.domain)/\(job.label)")
                    continue
                }
                try installer.bootout(label: job.label, domain: job.domain)
                actions.append("unloaded \(job.domain)/\(job.label)")
            }
            if global.json {
                try emitJSON(["actions": actions, "dryRun": dryRun])
            } else {
                for action in actions {
                    print(action)
                }
            }
        }
    }
}

struct Resume: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Load previously installed KeepAwake launchd jobs."
    )

    @OptionGroup var global: GlobalOptions
    @Flag(name: .long, help: "Only resume per-user LaunchAgents.")
    var agent = false
    @Flag(name: .long, help: "Only resume system LaunchDaemons. Requires root.")
    var daemon = false
    @Option(name: .long, help: "Only resume this launchd label.")
    var label: String?

    func run() throws {
        try runCommand {
            if agent, daemon {
                throw KeepAwakeError.invalidArgument("Choose either --agent or --daemon.")
            }
            let jobs = try targetedJobs(agent: agent, daemon: daemon, label: label)
            if jobs.isEmpty {
                print("No KeepAwake launchd jobs were installed.")
                return
            }
            let installer = LaunchdInstaller(launchctl: SystemLaunchctl(), adjustOwnership: false)
            var actions: [String] = []
            for job in jobs {
                try installer.bootstrap(
                    label: job.label,
                    domain: job.domain,
                    plistPath: URL(fileURLWithPath: job.plistPath)
                )
                actions.append("loaded \(job.domain)/\(job.label)")
            }
            if global.json {
                try emitJSON(["actions": actions])
            } else {
                for action in actions { print(action) }
            }
        }
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show KeepAwake jobs, sessions, and active power assertions."
    )

    @OptionGroup var global: GlobalOptions
    @Option(name: .long, help: "Only show this launchd label.")
    var label: String?
    @Flag(name: .customLong("keepawake-only"), help: "Only list assertions owned by KeepAwake.")
    var keepAwakeOnly = false

    func run() throws {
        try runCommand {
            let report = collectStatus(defaultStatusQuery(label: label, keepAwakeOnly: keepAwakeOnly))
            if global.json {
                try emitJSON(statusJSON(report))
            } else {
                for line in statusLines(report) {
                    print(line)
                }
            }
        }
    }
}

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install and load a LaunchAgent or LaunchDaemon that runs keepawake."
    )

    @OptionGroup var global: GlobalOptions
    @OptionGroup var assertion: AssertionOptions
    @Flag(name: .long, help: "Install a per-user LaunchAgent. This is the default.")
    var agent = false
    @Flag(name: .long, help: "Install a system LaunchDaemon. Requires root.")
    var daemon = false
    @Option(name: .long, help: "launchd label. Defaults to com.keepawake.agent or com.keepawake.daemon.")
    var label: String?
    @Option(name: .long, help: "Absolute or relative path of the keepawake binary. Defaults to this executable.")
    var binary: String?
    @Flag(name: .customLong("no-copy"), help: "Reference the binary in place instead of copying it into Application Support.")
    var noCopy = false
    @Option(name: .long, help: "Unix user for a LaunchAgent installed as root, for example from Jamf.")
    var user: String?
    @Flag(name: .customLong("keep-alive"), help: "Restart the job if it exits. This is the default for indefinite, schedule, and process watches.")
    var keepAlive = false
    @Flag(name: .customLong("no-keep-alive"), help: "Do not restart the job after it exits. This is the default for --duration and --until.")
    var noKeepAlive = false

    func run() throws {
        try runCommand {
            if agent, daemon {
                throw KeepAwakeError.invalidArgument("Choose either --agent or --daemon.")
            }
            if keepAlive, noKeepAlive {
                throw KeepAwakeError.invalidArgument("Choose either --keep-alive or --no-keep-alive.")
            }
            let loaded = try loadConfiguration(global)
            let scope: LaunchdScope = daemon ? .daemon : .agent
            if scope == .daemon, !loaded.config.allowSystemDaemon {
                throw KeepAwakeError.policyDenied("Managed preferences do not allow a LaunchDaemon.")
            }
            if scope == .agent, !loaded.config.allowUserAgent {
                throw KeepAwakeError.policyDenied("Managed preferences do not allow a LaunchAgent.")
            }
            let account = try resolveAccount(scope: scope, user: user)
            let request = try RequestResolver.resolve(
                assertion.makeInput(),
                config: loaded.config,
                now: Date(),
                calendar: .current,
                context: .install
            )
            let resolvedLabel = label ?? (scope == .daemon ? KeepAwake.daemonLabel : KeepAwake.agentLabel)
            try validateLaunchdLabel(resolvedLabel)
            let locations = InstallLayout.make(scope: scope, account: account)
            let source = binary.map(absoluteFileURL) ?? URL(fileURLWithPath: currentExecutablePath())
            let binaryPath = noCopy ? source.path : locations.copiedBinaryURL.path
            let arguments = request.launchArguments(binary: binaryPath)
            let keep = keepAlive ? true : (noKeepAlive ? false : request.mode.keepsAliveByDefault)
            let spec = LaunchdSpec(
                label: resolvedLabel,
                programArguments: arguments,
                runAtLoad: true,
                keepAlive: keep,
                limitLoadToSessionType: scope == .agent ? "Aqua" : nil,
                processType: scope == .agent ? "Interactive" : nil,
                throttleInterval: 10,
                standardOutPath: locations.logDirectory.appendingPathComponent("keepawake.out.log").path,
                standardErrorPath: locations.logDirectory.appendingPathComponent("keepawake.err.log").path
            )
            let xml = PlistXML.renderLaunchd(spec)
            if assertion.dryRun {
                if global.json {
                    try emitJSON([
                        "dryRun": true,
                        "label": resolvedLabel,
                        "scope": scope.rawValue,
                        "domain": locations.domain,
                        "plist": locations.plistURL(label: resolvedLabel).path,
                        "binary": binaryPath,
                        "arguments": arguments,
                        "plistXML": xml,
                    ])
                } else {
                    print("Dry run. No files were written.")
                    print("Scope: \(scope == .daemon ? "LaunchDaemon" : "LaunchAgent")")
                    print("Label: \(resolvedLabel)")
                    print("Domain: \(locations.domain)")
                    print("Plist: \(locations.plistURL(label: resolvedLabel).path)")
                    print("Binary: \(binaryPath)")
                    print(xml)
                }
                return
            }
            let installer = LaunchdInstaller(
                launchctl: SystemLaunchctl(),
                adjustOwnership: isRootUser()
            )
            let installed = try installer.install(
                request: InstallRequest(
                    label: resolvedLabel,
                    scope: scope,
                    programArguments: arguments,
                    keepAlive: keep,
                    binarySource: source,
                    copyBinary: !noCopy
                ),
                locations: locations
            )
            if global.json {
                try emitJSON([
                    "label": installed.label,
                    "scope": installed.scope.rawValue,
                    "plist": installed.plistPath,
                    "binary": installed.binaryPath,
                    "domain": installed.domain,
                    "arguments": installed.programArguments,
                ])
            } else {
                print("Installed \(scope == .daemon ? "LaunchDaemon" : "LaunchAgent") \(installed.label)")
                print("Plist: \(installed.plistPath)")
                print("Binary: \(installed.binaryPath)")
                print("Domain: \(installed.domain)")
            }
        }
    }
}

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove an installed LaunchAgent or LaunchDaemon."
    )

    @OptionGroup var global: GlobalOptions
    @Flag(name: .long, help: "Only remove per-user LaunchAgents.")
    var agent = false
    @Flag(name: .long, help: "Only remove system LaunchDaemons. Requires root.")
    var daemon = false
    @Option(name: .long, help: "Only remove this launchd label.")
    var label: String?
    @Flag(name: .long, help: "Also delete the copied binary in Application Support.")
    var purge = false
    @Flag(name: .customLong("dry-run"), help: "Print the jobs that would be removed.")
    var dryRun = false

    func run() throws {
        try runCommand {
            if agent, daemon {
                throw KeepAwakeError.invalidArgument("Choose either --agent or --daemon.")
            }
            let jobs = try targetedJobs(agent: agent, daemon: daemon, label: label)
            if jobs.isEmpty {
                print("No KeepAwake launchd jobs were installed.")
                return
            }
            if dryRun {
                let paths = jobs.map(\.plistPath)
                if global.json {
                    try emitJSON(["dryRun": true, "plists": paths])
                } else {
                    print("Dry run. No files were removed.")
                    for path in paths { print(path) }
                }
                return
            }
            let installer = LaunchdInstaller(launchctl: SystemLaunchctl(), adjustOwnership: false)
            var removed: [String] = []
            for job in jobs {
                guard let locations = locations(for: job) else { continue }
                let report = try installer.uninstall(label: job.label, locations: locations, purgeBinary: purge)
                removed.append(report.plistPath)
            }
            if global.json {
                try emitJSON(["removed": removed, "purge": purge])
            } else {
                for path in removed {
                    print("Removed \(path)")
                }
            }
        }
    }
}

struct ScheduleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Show whether a weekly schedule is active and when it next changes."
    )

    @OptionGroup var global: GlobalOptions
    @Argument(parsing: .remaining, help: "Schedule specification. Example: Mon-Fri 09:00-17:00")
    var words: [String] = []

    func run() throws {
        try runCommand {
            let spec = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spec.isEmpty else {
                throw KeepAwakeError.invalidSchedule("Pass a schedule. Example: keepawake schedule \"Mon-Fri 09:00-17:00\"")
            }
            let schedule = try parseSchedule(spec)
            let calendar = Calendar.current
            let now = Date()
            if global.json {
                try emitJSON(scheduleJSON(schedule, now: now, calendar: calendar))
            } else {
                for line in scheduleLines(schedule, now: now, calendar: calendar) {
                    print(line)
                }
            }
        }
    }
}

struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show the effective KeepAwake configuration."
    )

    @OptionGroup var global: GlobalOptions

    func run() throws {
        try runCommand {
            let loaded = try loadConfiguration(global)
            if global.json {
                try emitJSON(ManagedConfigLoader.jsonObject(for: loaded))
            } else {
                for line in ManagedConfigLoader.lines(for: loaded) {
                    print(line)
                }
            }
        }
    }
}

private func runCommand(_ body: () throws -> Void) throws {
    do {
        try body()
    } catch let error as ValidationError {
        throw error
    } catch let error as ExitCode {
        throw error
    } catch let error as KeepAwakeError {
        fputs("keepawake: \(error.description)\n", stderr)
        throw ExitCode(error.exitCode)
    } catch {
        fputs("keepawake: \(error.localizedDescription)\n", stderr)
        throw ExitCode(1)
    }
}

private func loadConfiguration(_ global: GlobalOptions) throws -> ConfigLoadResult {
    let result = try ManagedConfigLoader.loadDefault(extraPath: global.config)
    if !global.quiet {
        for warning in result.warnings {
            fputs("keepawake: \(warning)\n", stderr)
        }
    }
    return result
}

private func resolveAccount(scope: LaunchdScope, user: String?) throws -> Account {
    if scope == .daemon {
        guard isRootUser() else {
            throw KeepAwakeError.notRoot("Installing a LaunchDaemon requires root.")
        }
        return currentAccount()
    }
    if let user {
        guard isRootUser() else {
            throw KeepAwakeError.notRoot(
                "Installing a LaunchAgent for another user requires root. Run as that user, or run as root with --user."
            )
        }
        guard let match = account(named: user) else {
            throw KeepAwakeError.invalidArgument("Unknown user \"\(user)\".")
        }
        return match
    }
    if isRootUser() {
        throw KeepAwakeError.notRoot(
            "Root is installing a LaunchAgent. Pass --user <name>, or pass --daemon for a system job."
        )
    }
    return currentAccount()
}

private func targetedSessions() -> [SessionState] {
    let query = defaultStatusQuery(label: nil, keepAwakeOnly: false)
    return SessionStore.loadAll(directories: query.sessionDirectories, removeStale: false)
}

private func targetedJobs(agent: Bool, daemon: Bool, label: String?) throws -> [JobSnapshot] {
    var jobs = collectStatus(defaultStatusQuery(label: label, keepAwakeOnly: false)).jobs
    if agent {
        jobs = jobs.filter { $0.scope == "LaunchAgent" }
    } else if daemon {
        jobs = jobs.filter { $0.scope == "LaunchDaemon" }
    }
    if daemon, !isRootUser() {
        throw KeepAwakeError.notRoot("Changing a LaunchDaemon requires root.")
    }
    if !isRootUser(), jobs.contains(where: { $0.scope == "LaunchDaemon" }) {
        fputs("keepawake: skipping LaunchDaemons because this command is not root.\n", stderr)
        jobs = jobs.filter { $0.scope != "LaunchDaemon" }
    }
    return jobs
}

private func locations(for job: JobSnapshot) -> InstallLocations? {
    if job.scope == "LaunchDaemon" {
        var system = InstallLayout.make(scope: .daemon, account: currentAccount())
        system.domain = job.domain
        return system
    }
    let home = URL(fileURLWithPath: job.plistPath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let owner = Account(name: home.lastPathComponent, uid: 0, gid: 0, home: home)
    var userLocations = InstallLayout.make(scope: .agent, account: owner)
    userLocations.domain = job.domain
    return userLocations
}

private func scheduleLines(_ schedule: WeeklySchedule, now: Date, calendar: Calendar) -> [String] {
    var lines = [
        "Schedule: \(schedule.source)",
        "Time zone: \(calendar.timeZone.identifier)",
        "Now: \(formatTimestamp(now, calendar: calendar))",
        "Active: \(schedule.contains(now, calendar: calendar) ? "yes" : "no")",
    ]
    if let next = schedule.nextTransition(after: now, calendar: calendar) {
        lines.append("Next change: \(formatTimestamp(next, calendar: calendar))")
    } else {
        lines.append("Next change: none within 8 days")
    }
    lines.append("Windows:")
    for window in schedule.windows {
        lines.append("  \(describeWindow(window))")
    }
    return lines
}

private func scheduleJSON(_ schedule: WeeklySchedule, now: Date, calendar: Calendar) -> [String: Any] {
    let windows: [[String: Any]] = schedule.windows.map { window in
        [
            "days": describeWeekdays(window.weekdays).split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            },
            "start": window.start.formatted,
            "end": window.end.formatted,
            "seconds": Int(window.duration),
        ]
    }
    var object: [String: Any] = [
        "source": schedule.source,
        "timeZone": calendar.timeZone.identifier,
        "now": formatISO8601(now),
        "active": schedule.contains(now, calendar: calendar),
        "windows": windows,
    ]
    if let next = schedule.nextTransition(after: now, calendar: calendar) {
        object["nextChange"] = formatISO8601(next)
    } else {
        object["nextChange"] = NSNull()
    }
    return object
}

private func emitJSON(_ object: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
