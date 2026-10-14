import XCTest
@testable import KeepAwakeCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class DurationParserTests: XCTestCase {
    func testUnits() throws {
        XCTAssertEqual(try parseDuration("90"), 90)
        XCTAssertEqual(try parseDuration("90s"), 90)
        XCTAssertEqual(try parseDuration("45m"), 2_700)
        XCTAssertEqual(try parseDuration("2h"), 7_200)
        XCTAssertEqual(try parseDuration("1h30m"), 5_400)
        XCTAssertEqual(try parseDuration("1.5h"), 5_400)
        XCTAssertEqual(try parseDuration("2 hours"), 7_200)
        XCTAssertEqual(try parseDuration("1d2h"), 93_600)
    }

    func testRejectsEmptyZeroAndMissingUnit() {
        XCTAssertThrowsError(try parseDuration(""))
        XCTAssertThrowsError(try parseDuration("0s"))
        XCTAssertThrowsError(try parseDuration("1h30"))
        XCTAssertThrowsError(try parseDuration("soon"))
    }

    func testFormatDuration() {
        XCTAssertEqual(formatDuration(90), "1m30s")
        XCTAssertEqual(formatDuration(7_200), "2h")
        XCTAssertEqual(formatDuration(5_400), "1h30m")
        XCTAssertEqual(formatDuration(90_000), "1d1h")
    }
}

final class ClockTimeTests: XCTestCase {
    func testClockLaterTodayAndRollover() throws {
        let calendar = utcCalendar()
        let now = try utcDate(2026, 10, 14, 12, 0, calendar: calendar)
        let later = try parseUntil("17:30", now: now, calendar: calendar)
        XCTAssertEqual(later, try utcDate(2026, 10, 14, 17, 30, calendar: calendar))
        let rolled = try parseUntil("9:00am", now: now, calendar: calendar)
        XCTAssertEqual(rolled, try utcDate(2026, 10, 15, 9, 0, calendar: calendar))
        let afternoon = try parseUntil("5:30pm", now: now, calendar: calendar)
        XCTAssertEqual(afternoon, try utcDate(2026, 10, 14, 17, 30, calendar: calendar))
    }

    func testAbsoluteDate() throws {
        let calendar = utcCalendar()
        let now = try utcDate(2026, 10, 14, 12, 0, calendar: calendar)
        let parsed = try parseUntil("2026-10-14 18:00", now: now, calendar: calendar)
        XCTAssertEqual(parsed, try utcDate(2026, 10, 14, 18, 0, calendar: calendar))
        XCTAssertThrowsError(try parseUntil("2026-10-14 08:00", now: now, calendar: calendar))
    }
}

final class WeeklyScheduleTests: XCTestCase {
    func testWeekdayWindow() throws {
        let calendar = utcCalendar()
        let schedule = try parseSchedule("Mon-Fri 09:00-17:00")
        let noon = try utcDate(2026, 10, 14, 12, 0, calendar: calendar)
        XCTAssertTrue(schedule.contains(noon, calendar: calendar))
        XCTAssertEqual(
            schedule.nextTransition(after: noon, calendar: calendar),
            try utcDate(2026, 10, 14, 17, 0, calendar: calendar)
        )
        let evening = try utcDate(2026, 10, 14, 18, 0, calendar: calendar)
        XCTAssertFalse(schedule.contains(evening, calendar: calendar))
        XCTAssertEqual(
            schedule.nextTransition(after: evening, calendar: calendar),
            try utcDate(2026, 10, 15, 9, 0, calendar: calendar)
        )
        let saturday = try utcDate(2026, 10, 17, 12, 0, calendar: calendar)
        XCTAssertEqual(
            schedule.nextTransition(after: saturday, calendar: calendar),
            try utcDate(2026, 10, 19, 9, 0, calendar: calendar)
        )
    }

    func testOvernightAndWrappedDays() throws {
        let calendar = utcCalendar()
        let schedule = try parseSchedule("Fri 22:00-06:00")
        let fridayNight = try utcDate(2026, 10, 16, 23, 0, calendar: calendar)
        let saturdayEarly = try utcDate(2026, 10, 17, 3, 0, calendar: calendar)
        let saturdayMorning = try utcDate(2026, 10, 17, 7, 0, calendar: calendar)
        XCTAssertTrue(schedule.contains(fridayNight, calendar: calendar))
        XCTAssertTrue(schedule.contains(saturdayEarly, calendar: calendar))
        XCTAssertFalse(schedule.contains(saturdayMorning, calendar: calendar))
        XCTAssertEqual(schedule.windows[0].duration, 8 * 3_600)

        let wrapped = try parseSchedule("Fri-Mon 10:00-11:00")
        XCTAssertEqual(wrapped.windows[0].weekdays, [6, 7, 1, 2])
        XCTAssertThrowsError(try parseSchedule("Mon-Fri 17:00-17:00"))
        XCTAssertThrowsError(try parseSchedule("Mon-Fri"))
    }

    func testFullDayAndMultipleWindows() throws {
        let calendar = utcCalendar()
        let schedule = try parseSchedule("all 00:00-24:00; Sat 12:00-13:00")
        let noon = try utcDate(2026, 10, 14, 12, 30, calendar: calendar)
        XCTAssertTrue(schedule.contains(noon, calendar: calendar))
        XCTAssertEqual(schedule.windows[0].duration, 86_400)
        let listed = try parseSchedule("Mon, Wed, Fri 08:30-12:00")
        XCTAssertEqual(listed.windows[0].weekdays, [2, 4, 6])
    }
}

final class ManagedConfigTests: XCTestCase {
    func testMergeOrderAndInvalidType() throws {
        let directory = temporaryDirectory()
        let user = directory.appendingPathComponent("user.plist")
        let managed = directory.appendingPathComponent("managed.plist")
        try writePlist(user, ["Reason": "local", "Disabled": false])
        try writePlist(managed, ["Reason": "managed", "MaximumDurationSeconds": 3_600])
        let loaded = try ManagedConfigLoader.load(layers: [
            ConfigLayer(url: user, role: "user defaults"),
            ConfigLayer(url: managed, role: "managed preferences"),
        ])
        XCTAssertEqual(loaded.config.reason, "managed")
        XCTAssertEqual(loaded.config.maximumDurationSeconds, 3_600)
        XCTAssertEqual(loaded.files.count, 2)

        let broken = directory.appendingPathComponent("broken.plist")
        try plistWrap("<key>Disabled</key><string>nope</string>").write(to: broken, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ManagedConfigLoader.load(layers: [ConfigLayer(url: broken, role: "managed")]))
    }

    func testUnknownKeyWarningAndSampleProfile() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("extra.plist")
        try writePlist(url, ["Disabled": false, "NotAKey": "x"])
        let loaded = try ManagedConfigLoader.load(layers: [ConfigLayer(url: url, role: "extra")])
        XCTAssertEqual(loaded.warnings.count, 1)

        let root = repositoryRoot()
        let sample = try ManagedConfigLoader.load(layers: [
            ConfigLayer(url: root.appendingPathComponent("Configuration/com.keepawake.plist"), role: "sample"),
        ])
        XCTAssertFalse(sample.config.disabled)
        XCTAssertFalse(sample.config.enforceSchedule)
        XCTAssertEqual(sample.config.defaultSchedule, "Mon-Fri 08:00-18:00")
        XCTAssertNil(sample.config.maximumDurationSeconds)
        XCTAssertTrue(sample.warnings.isEmpty)

        let profile = try Data(contentsOf: root.appendingPathComponent("Configuration/KeepAwake.mobileconfig"))
        let object = try PropertyListSerialization.propertyList(from: profile, options: [], format: nil) as? [String: Any]
        XCTAssertEqual(object?["PayloadType"] as? String, "Configuration")
        let payloads = object?["PayloadContent"] as? [[String: Any]]
        XCTAssertEqual(payloads?.first?["PayloadType"] as? String, KeepAwake.preferenceDomain)
    }
}

final class RequestResolverTests: XCTestCase {
    func testDefaults() throws {
        let calendar = utcCalendar()
        let now = try utcDate(2026, 10, 14, 12, 0, calendar: calendar)
        let request = try RequestResolver.resolve(
            StartInput(),
            config: .permissive,
            now: now,
            calendar: calendar,
            context: .start
        )
        XCTAssertEqual(request.mode, .indefinite)
        XCTAssertEqual(request.profile, .standard)
        XCTAssertEqual(request.reason, KeepAwake.defaultReason)
        XCTAssertEqual(request.launchArguments(binary: "/usr/local/bin/keepawake"), [
            "/usr/local/bin/keepawake", "start", "--indefinite",
            "--display", "--idle-system",
            "--reason", "KeepAwake", "--backend", "auto",
        ])
    }

    func testInstallUsesDefaultSchedule() throws {
        let calendar = utcCalendar()
        let now = try utcDate(2026, 10, 14, 12, 0, calendar: calendar)
        var config = ManagedConfig.permissive
        config.defaultSchedule = "Mon-Fri 09:00-17:00"
        let installed = try RequestResolver.resolve(StartInput(), config: config, now: now, calendar: calendar, context: .install)
        guard case .schedule(let schedule) = installed.mode else {
            return XCTFail("Expected the default schedule")
        }
        XCTAssertEqual(schedule.source, "Mon-Fri 09:00-17:00")
        let started = try RequestResolver.resolve(StartInput(), config: config, now: now, calendar: calendar, context: .start)
        XCTAssertEqual(started.mode, .indefinite)
    }

    func testPolicyLimits() throws {
        let calendar = utcCalendar()
        let now = try utcDate(2026, 10, 14, 12, 0, calendar: calendar)
        var capped = ManagedConfig.permissive
        capped.maximumDurationSeconds = 3_600
        XCTAssertThrowsError(try RequestResolver.resolve(StartInput(), config: capped, now: now, calendar: calendar, context: .start))
        XCTAssertThrowsError(try RequestResolver.resolve(StartInput(duration: "2h"), config: capped, now: now, calendar: calendar, context: .start))
        XCTAssertNoThrow(try RequestResolver.resolve(StartInput(duration: "30m"), config: capped, now: now, calendar: calendar, context: .start))
        XCTAssertThrowsError(try RequestResolver.resolve(StartInput(whileApp: "zoom.us"), config: capped, now: now, calendar: calendar, context: .start))

        var enforced = ManagedConfig.permissive
        enforced.enforceSchedule = true
        enforced.defaultSchedule = "Mon-Fri 09:00-17:00"
        XCTAssertThrowsError(try RequestResolver.resolve(StartInput(duration: "1h"), config: enforced, now: now, calendar: calendar, context: .start))
        XCTAssertNoThrow(try RequestResolver.resolve(StartInput(schedule: "Mon-Fri 09:00-17:00"), config: enforced, now: now, calendar: calendar, context: .start))

        var disabled = ManagedConfig.permissive
        disabled.disabled = true
        XCTAssertThrowsError(try RequestResolver.resolve(StartInput(duration: "1m"), config: disabled, now: now, calendar: calendar, context: .start))

        var longNight = ManagedConfig.permissive
        longNight.maximumDurationSeconds = 7 * 3_600
        XCTAssertThrowsError(try RequestResolver.resolve(
            StartInput(schedule: "Mon-Fri 22:00-06:00"),
            config: longNight,
            now: now,
            calendar: calendar,
            context: .start
        ))
    }

    func testLockedProfileAndBackend() throws {
        let calendar = utcCalendar()
        let now = try utcDate(2026, 10, 14, 12, 0, calendar: calendar)
        var config = ManagedConfig.permissive
        config.lockAssertionProfile = true
        config.preventDisplaySleep = true
        config.preventIdleSystemSleep = false
        config.preventSystemSleep = false
        config.preventDiskIdle = false
        let allowed = try RequestResolver.resolve(StartInput(), config: config, now: now, calendar: calendar, context: .start)
        XCTAssertTrue(allowed.profile.preventDisplaySleep)
        XCTAssertFalse(allowed.profile.preventIdleSystemSleep)
        XCTAssertThrowsError(try RequestResolver.resolve(
            StartInput(display: true, idleSystem: true),
            config: config,
            now: now,
            calendar: calendar,
            context: .start
        ))

        config.lockBackend = true
        config.backend = "caffeinate"
        let backend = try RequestResolver.resolve(StartInput(), config: config, now: now, calendar: calendar, context: .start)
        XCTAssertEqual(backend.backend, .caffeinate)
        XCTAssertThrowsError(try RequestResolver.resolve(
            StartInput(backend: "iokit"),
            config: config,
            now: now,
            calendar: calendar,
            context: .start
        ))
    }

    func testCaffeinateArguments() throws {
        let calendar = utcCalendar()
        let now = try utcDate(2026, 10, 14, 12, 0, calendar: calendar)
        let request = try RequestResolver.resolve(
            StartInput(duration: "2h", display: true, idleSystem: true, disk: true, userActivity: true),
            config: .permissive,
            now: now,
            calendar: calendar,
            context: .start
        )
        XCTAssertEqual(caffeinateArguments(for: request, now: now), ["-dimu", "-t", "7200"])
        XCTAssertFalse(request.mode.keepsAliveByDefault)
        XCTAssertTrue(HoldMode.indefinite.keepsAliveByDefault)
    }
}

final class PlistAndStatusTests: XCTestCase {
    func testPlistRoundTripEscapesText() throws {
        let spec = LaunchdSpec(
            label: "com.keepawake.agent",
            programArguments: ["/usr/local/bin/keepawake", "start", "--reason", "A & B <C>"],
            runAtLoad: true,
            keepAlive: false,
            limitLoadToSessionType: "Aqua",
            processType: "Interactive",
            throttleInterval: 10,
            standardOutPath: "/tmp/keepawake.out.log",
            standardErrorPath: "/tmp/keepawake.err.log"
        )
        let xml = PlistXML.renderLaunchd(spec)
        XCTAssertTrue(xml.contains("A &amp; B &lt;C&gt;"))
        let parsed = try PropertyListSerialization.propertyList(from: Data(xml.utf8), options: [], format: nil) as? [String: Any]
        XCTAssertEqual(parsed?["Label"] as? String, "com.keepawake.agent")
        XCTAssertEqual(boolish(parsed?["KeepAlive"]), false)
        XCTAssertEqual(boolish(parsed?["RunAtLoad"]), true)
        XCTAssertEqual(parsed?["ProgramArguments"] as? [String], spec.programArguments)
    }

    func testPMSetAndLaunchctlParsing() {
        let text = """
        Assertion status system-wide:
           PreventUserIdleDisplaySleep    1
           PreventUserIdleSystemSleep     1
           PreventSystemSleep             0
        Listed by owning process:
           pid 533(keepawake): [0x0001] 00:01:02 PreventUserIdleSystemSleep named: "KeepAwake"
           pid 88(WindowServer): [0x0002] 00:00:05 UserIsActive named: "com.apple.whatever"
        No assertions.
        """
        let report = parsePMSetAssertions(text)
        XCTAssertEqual(report.counts["PreventUserIdleDisplaySleep"], 1)
        XCTAssertEqual(report.assertions.count, 2)
        XCTAssertTrue(report.assertions[0].ownedByKeepAwake)
        XCTAssertFalse(report.assertions[1].ownedByKeepAwake)

        let printed = """
        gui/501/com.keepawake.agent = {
        \tstate = running
        \tpid = 4321
        \tprogram = /usr/local/bin/keepawake
        }
        """
        let info = parseLaunchctlPrint(printed)
        XCTAssertEqual(info.state, "running")
        XCTAssertEqual(info.pid, 4_321)
    }

    func testProcessMatching() {
        let records = parseProcessList("""
          42 zoom.us /Applications/zoom.us.app/Contents/MacOS/zoom.us --url
          7 backupd /usr/libexec/backupd
        """)
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(appIsRunning(named: "zoom.us", in: records))
        XCTAssertTrue(processIsRunning(named: "backupd", in: records))
        XCTAssertFalse(processIsRunning(named: "Backupd", in: records))
        XCTAssertTrue(pidExists(Int32(getpid())))
    }

    func testStatusCollectionFiltersJobs() throws {
        let directory = temporaryDirectory()
        let agents = directory.appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let ours = agents.appendingPathComponent("com.keepawake.agent.plist")
        let other = agents.appendingPathComponent("com.example.other.plist")
        try PlistXML.renderLaunchd(LaunchdSpec(
            label: "com.keepawake.agent",
            programArguments: ["/usr/local/bin/keepawake", "start", "--indefinite"],
            runAtLoad: true,
            keepAlive: true,
            limitLoadToSessionType: "Aqua",
            processType: "Interactive",
            throttleInterval: 10,
            standardOutPath: "/tmp/out.log",
            standardErrorPath: "/tmp/err.log"
        )).write(to: ours, atomically: true, encoding: .utf8)
        try PlistXML.renderLaunchd(LaunchdSpec(
            label: "com.example.other",
            programArguments: ["/usr/bin/true"],
            runAtLoad: true,
            keepAlive: false,
            limitLoadToSessionType: nil,
            processType: nil,
            throttleInterval: 10,
            standardOutPath: "/tmp/out.log",
            standardErrorPath: "/tmp/err.log"
        )).write(to: other, atomically: true, encoding: .utf8)
        let pmset = """
        Assertion status system-wide:
           PreventUserIdleSystemSleep     1
        Listed by owning process:
           pid 9(keepawake): [0x1] 00:00:01 PreventUserIdleSystemSleep named: "KeepAwake"
        """
        let report = collectStatus(StatusQuery(
            plistDirectories: [agents],
            sessionDirectories: [],
            domain: { _ in "gui/501" },
            scopeName: { _ in "LaunchAgent" },
            run: { executable, arguments in
                if executable.hasSuffix("pmset") {
                    return CommandResult(status: 0, stdout: pmset, stderr: "")
                }
                XCTAssertEqual(arguments.first, "print")
                return CommandResult(status: 0, stdout: "state = running\npid = 9\n", stderr: "")
            },
            label: nil,
            keepAwakeOnly: true,
            removeStaleSessions: false
        ))
        XCTAssertEqual(report.jobs.map(\.label), ["com.keepawake.agent"])
        XCTAssertEqual(report.jobs.first?.pid, 9)
        XCTAssertEqual(report.power.assertions.count, 1)
        XCTAssertTrue(statusLines(report).contains { $0.contains("com.keepawake.agent") })
    }
}

final class LaunchdInstallerTests: XCTestCase {
    func testInstallAndUninstall() throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("keepawake")
        try "#!/bin/sh\nexit 0\n".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        let locations = InstallLocations(
            plistDirectory: root.appendingPathComponent("agents", isDirectory: true),
            logDirectory: root.appendingPathComponent("logs", isDirectory: true),
            binaryDirectory: root.appendingPathComponent("support", isDirectory: true),
            domain: "gui/501",
            uid: 501,
            gid: 20
        )
        let launchctl = FakeLaunchctl()
        let installer = LaunchdInstaller(launchctl: launchctl, adjustOwnership: false)
        let installed = try installer.install(
            request: InstallRequest(
                label: "com.keepawake.agent",
                scope: .agent,
                programArguments: [source.path, "start", "--schedule", "Mon-Fri 09:00-17:00"],
                keepAlive: true,
                binarySource: source,
                copyBinary: true
            ),
            locations: locations
        )
        XCTAssertEqual(installed.binaryPath, locations.copiedBinaryURL.path)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installed.binaryPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.plistPath))
        XCTAssertEqual(launchctl.calls.contains { $0.first == "bootstrap" }, true)
        let parsed = try plistDictionary(at: URL(fileURLWithPath: installed.plistPath))
        XCTAssertEqual(parsed["ProgramArguments"] as? [String], [
            locations.copiedBinaryURL.path, "start", "--schedule", "Mon-Fri 09:00-17:00",
        ])

        launchctl.results["bootout"] = CommandResult(status: 3, stdout: "", stderr: "Boot-out failed: 3: No such process")
        let report = try installer.uninstall(label: "com.keepawake.agent", locations: locations, purgeBinary: true)
        XCTAssertTrue(report.plistRemoved)
        XCTAssertTrue(report.binaryRemoved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.plistPath))
    }

    func testBootstrapFailure() throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("keepawake")
        try Data("binary".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        let locations = InstallLocations(
            plistDirectory: root.appendingPathComponent("daemons", isDirectory: true),
            logDirectory: root.appendingPathComponent("logs", isDirectory: true),
            binaryDirectory: root.appendingPathComponent("support", isDirectory: true),
            domain: "system",
            uid: 0,
            gid: 0
        )
        let launchctl = FakeLaunchctl()
        launchctl.results["bootstrap"] = CommandResult(status: 5, stdout: "", stderr: "Bootstrap failed")
        let installer = LaunchdInstaller(launchctl: launchctl, adjustOwnership: false)
        XCTAssertThrowsError(try installer.install(
            request: InstallRequest(
                label: "com.keepawake.daemon",
                scope: .daemon,
                programArguments: [source.path, "start", "--indefinite"],
                keepAlive: true,
                binarySource: source,
                copyBinary: false
            ),
            locations: locations
        ))
    }
}

final class RepositoryTextTests: XCTestCase {
    func testReadmeAndNoEmDashes() throws {
        let root = repositoryRoot()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        for phrase in [
            "keepawake start",
            "keepawake install",
            "keepawake status",
            "keepawake uninstall",
            "Jamf",
            "--duration",
            "--schedule",
            "LaunchDaemon",
            "com.keepawake",
        ] {
            XCTAssertTrue(readme.contains(phrase), "README is missing \(phrase)")
        }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        let allowed: Set<String> = ["swift", "md", "yml", "yaml", "sh", "plist", "mobileconfig", "1"]
        while let url = enumerator?.nextObject() as? URL {
            let path = url.path
            if path.contains("/.git/") || path.contains("/.build/") || path.contains("/.swiftpm/") {
                continue
            }
            let name = url.lastPathComponent
            guard allowed.contains(url.pathExtension) || name == "LICENSE" || name == "Makefile" || name == ".gitignore" else {
                continue
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains("\u{2014}"), "Em dash in \(path)")
        }
    }

    func testCheckTextScriptPasses() throws {
        let root = repositoryRoot()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("Scripts/check-text.sh").path]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, output + errorOutput)
    }

    func testShellScriptsParse() throws {
        let root = repositoryRoot()
        let scripts = [
            "Examples/Jamf/install-keepawake.sh",
            "Examples/Jamf/uninstall-keepawake.sh",
            "Scripts/build-universal.sh",
            "Scripts/package-menu-app.sh",
            "Scripts/build-pkg.sh",
            "Scripts/check-text.sh",
        ]
        for relative in scripts {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-n", root.appendingPathComponent(relative).path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, relative)
        }
    }
}

final class FakeLaunchctl: LaunchctlClient {
    var calls: [[String]] = []
    var results: [String: CommandResult] = [:]

    func run(_ arguments: [String]) -> CommandResult {
        calls.append(arguments)
        return results[arguments.first ?? ""] ?? CommandResult(status: 0, stdout: "", stderr: "")
    }
}

func utcCalendar() -> Calendar {
    posixCalendar(timeZone: TimeZone(secondsFromGMT: 0))
}

func utcDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int,
    calendar: Calendar
) throws -> Date {
    var parts = DateComponents()
    parts.year = year
    parts.month = month
    parts.day = day
    parts.hour = hour
    parts.minute = minute
    parts.second = 0
    guard let date = calendar.date(from: parts) else {
        throw KeepAwakeError.invalidTime("Could not build a test date.")
    }
    return date
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("keepawake-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writePlist(_ url: URL, _ dictionary: [String: Any]) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    try data.write(to: url)
}

func plistWrap(_ body: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    \(body)
    </dict></plist>
    """
}

func boolish(_ value: Any?) -> Bool? {
    if let bool = value as? Bool { return bool }
    if let number = value as? NSNumber { return number.boolValue }
    return nil
}

func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
