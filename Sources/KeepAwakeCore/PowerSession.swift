import Foundation
#if canImport(IOKit)
import IOKit.pwr_mgt
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class PowerSession {
    private let flag = StopFlag()
    private let lock = NSLock()
    private var assertionIDs: [UInt32] = []
    private var caffeinateProcess: Process?
    private var holding = false
    private let installSignalHandlers: Bool
    private let log: (String) -> Void
    private var signalSources: [DispatchSourceSignal] = []
    private var installedSignals = false
    private var earlyExit: KeepAwakeError?

    public init(
        installSignalHandlers: Bool = true,
        log: @escaping (String) -> Void = { message in
            fputs(message + "\n", stderr)
        }
    ) {
        self.installSignalHandlers = installSignalHandlers
        self.log = log
    }

    public func cancel() {
        flag.stop()
        releaseHold()
    }

    public func run(_ request: ResolvedRequest) throws {
        installSignals()
        let directory = SessionStore.directoryForCurrentProcess()
        var acquiredOnce = false
        defer {
            releaseHold()
            SessionStore.remove(pid: Int32(getpid()), directory: directory)
            removeSignals()
            if acquiredOnce {
                log("Released the power assertion.")
            }
        }
        switch request.mode {
        case .whilePID(let pid):
            guard pidExists(pid) else {
                throw KeepAwakeError.processNotRunning("Process \(pid) is not running.")
            }
            let backend = try beginHold(request, timeout: nil, directory: directory, endsAt: nil)
            acquiredOnce = true
            while !flag.stopped, pidExists(pid) {
                try throwIfNeeded()
                refreshUserActivityIfNeeded(request, backend: backend)
                Thread.sleep(forTimeInterval: 0.5)
            }
        case .whileApp(let name):
            try watch(request, directory: directory, acquiredOnce: &acquiredOnce) {
                appIsRunning(named: name, in: liveProcessRecords())
            }
        case .whileProcess(let name):
            try watch(request, directory: directory, acquiredOnce: &acquiredOnce) {
                processIsRunning(named: name, in: liveProcessRecords())
            }
        default:
            try runTimed(request, directory: directory, acquiredOnce: &acquiredOnce)
        }
        if let earlyExit {
            throw earlyExit
        }
    }

    private func runTimed(
        _ request: ResolvedRequest,
        directory: URL,
        acquiredOnce: inout Bool
    ) throws {
        let startedAt = Date()
        let calendar = Calendar.current
        while !flag.stopped {
            let now = Date()
            switch sessionAction(mode: request.mode, now: now, startedAt: startedAt, calendar: calendar) {
            case .finished:
                return
            case .wait(let until):
                releaseHold()
                wait(until: until)
            case .hold(let until):
                if !isHolding {
                    let timeout = until.map { max(1, $0.timeIntervalSinceNow + 30) }
                    _ = try beginHold(request, timeout: timeout, directory: directory, endsAt: until)
                    acquiredOnce = true
                }
                refreshUserActivityIfNeeded(request, backend: currentBackend(fallback: request.backend))
                if let until {
                    wait(until: until)
                    releaseHold()
                } else {
                    wait(until: Date().addingTimeInterval(5))
                }
            }
            try throwIfNeeded()
        }
    }

    private func watch(
        _ request: ResolvedRequest,
        directory: URL,
        acquiredOnce: inout Bool,
        isRunning: () -> Bool
    ) throws {
        var seen = false
        var misses = 0
        while !flag.stopped {
            if isRunning() {
                seen = true
                misses = 0
                if !isHolding {
                    _ = try beginHold(request, timeout: nil, directory: directory, endsAt: nil)
                    acquiredOnce = true
                }
                try throwIfNeeded()
                refreshUserActivityIfNeeded(request, backend: currentBackend(fallback: request.backend))
            } else if seen {
                misses += 1
                if misses >= 3 {
                    return
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    @discardableResult
    private func beginHold(
        _ request: ResolvedRequest,
        timeout: TimeInterval?,
        directory: URL,
        endsAt: Date?
    ) throws -> AssertionBackend {
        let backend = try acquire(request, timeout: timeout)
        let state = SessionState(
            pid: Int32(getpid()),
            mode: modeLabel(request.mode),
            summary: request.summary,
            reason: request.reason,
            profile: request.profile.names,
            backend: backend.rawValue,
            startedAt: Date(),
            endsAt: endsAt
        )
        do {
            try SessionStore.write(state, directory: directory)
        } catch {
            log("Could not write the session file: \(error.localizedDescription)")
        }
        log("Holding a power assertion.")
        log("Mode: \(request.summary)")
        log("Profile: \(request.profile.summary)")
        log("Backend: \(backend.rawValue)")
        log("Reason: \(request.reason)")
        if let endsAt {
            log("Ends: \(formatTimestamp(endsAt, calendar: Calendar.current))")
        }
        if installSignalHandlers, isInteractiveStandardInput() {
            log("Press Control-C to release.")
        }
        return backend
    }

    private func acquire(_ request: ResolvedRequest, timeout: TimeInterval?) throws -> AssertionBackend {
        switch request.backend {
        case .iokit:
            try acquireIOKit(request.profile, reason: request.reason, timeout: timeout)
            return .iokit
        case .caffeinate:
            try acquireCaffeinate(request, timeout: timeout)
            return .caffeinate
        case .auto:
            #if canImport(IOKit)
            do {
                try acquireIOKit(request.profile, reason: request.reason, timeout: timeout)
                return .iokit
            } catch {
                log("IOKit assertion failed (\(error.localizedDescription)). Falling back to caffeinate.")
                releaseHold()
            }
            #endif
            try acquireCaffeinate(request, timeout: timeout)
            return .caffeinate
        }
    }

    private func acquireIOKit(_ profile: AssertionProfile, reason: String, timeout: TimeInterval?) throws {
        #if canImport(IOKit)
        let name = String(reason.prefix(128))
        let details = String(reason.prefix(512))
        let timeoutValue = timeout ?? 0
        let types: [(Bool, String)] = [
            (profile.preventDisplaySleep, "PreventUserIdleDisplaySleep"),
            (profile.preventIdleSystemSleep, "PreventUserIdleSystemSleep"),
            (profile.preventSystemSleep, "PreventSystemSleep"),
            (profile.preventDiskIdle, "PreventDiskIdle"),
        ]
        var created: [IOPMAssertionID] = []
        for (enabled, type) in types where enabled {
            var identifier: IOPMAssertionID = 0
            let described = IOPMAssertionCreateWithDescription(
                type as CFString,
                name as CFString,
                details as CFString,
                name as CFString,
                "" as CFString,
                timeoutValue,
                kIOPMAssertionTimeoutActionTurnOff as CFString,
                &identifier
            )
            if described == kIOReturnSuccess {
                created.append(identifier)
                continue
            }
            var fallback: IOPMAssertionID = 0
            let named = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                name as CFString,
                &fallback
            )
            guard named == kIOReturnSuccess else {
                releaseIdentifiers(created)
                throw KeepAwakeError.assertionFailed(
                    "IOKit could not create \(type) (description \(ioHex(described)), name \(ioHex(named)))."
                )
            }
            created.append(fallback)
        }
        lock.lock()
        assertionIDs.append(contentsOf: created.map { UInt32($0) })
        holding = true
        lock.unlock()
        #else
        throw KeepAwakeError.assertionFailed("IOKit power assertions are not available on this system.")
        #endif
    }

    private func acquireCaffeinate(_ request: ResolvedRequest, timeout: TimeInterval?) throws {
        let path = ProcessInfo.processInfo.environment["KEEP_AWAKE_CAFFEINATE"] ?? "/usr/bin/caffeinate"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw KeepAwakeError.assertionFailed("caffeinate was not found at \(path).")
        }
        var arguments = caffeinateArguments(for: request, now: Date())
        if let timeout, !arguments.contains("-t") {
            arguments.append(contentsOf: ["-t", String(max(1, Int(timeout.rounded(.up))))])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            throw KeepAwakeError.assertionFailed("Could not run caffeinate: \(error.localizedDescription)")
        }
        lock.lock()
        caffeinateProcess = process
        holding = true
        lock.unlock()
    }

    private func refreshUserActivityIfNeeded(_ request: ResolvedRequest, backend: AssertionBackend) {
        guard request.profile.declareUserActivity, backend == .iokit else { return }
        #if canImport(IOKit)
        var identifier: IOPMAssertionID = 0
        let name = String(request.reason.prefix(128))
        _ = IOPMAssertionDeclareUserActivity(name as CFString, kIOPMUserActiveLocal, &identifier)
        #endif
    }

    private func wait(until deadline: Date) {
        while !flag.stopped {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return }
            noteEarlyCaffeinateExit(remaining: remaining)
            let slice = min(remaining, remaining > 30 ? 5 : 0.5)
            Thread.sleep(forTimeInterval: slice)
        }
    }

    private func noteEarlyCaffeinateExit(remaining: TimeInterval) {
        lock.lock()
        let process = caffeinateProcess
        let active = holding
        lock.unlock()
        guard active, let process, !process.isRunning, remaining > 2, !flag.stopped else { return }
        earlyExit = KeepAwakeError.assertionFailed(
            "caffeinate exited early with status \(process.terminationStatus)."
        )
        flag.stop()
    }

    private func throwIfNeeded() throws {
        if let earlyExit {
            throw earlyExit
        }
    }

    private var isHolding: Bool {
        lock.lock()
        defer { lock.unlock() }
        return holding
    }

    private func currentBackend(fallback: AssertionBackend) -> AssertionBackend {
        lock.lock()
        let iokit = !assertionIDs.isEmpty
        let caffeine = caffeinateProcess != nil
        lock.unlock()
        if iokit { return .iokit }
        if caffeine { return .caffeinate }
        return fallback
    }

    private func releaseHold() {
        lock.lock()
        let process = caffeinateProcess
        caffeinateProcess = nil
        let identifiers = assertionIDs
        assertionIDs = []
        holding = false
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
        }
        #if canImport(IOKit)
        releaseIdentifiers(identifiers.map { IOPMAssertionID($0) })
        #endif
    }

    #if canImport(IOKit)
    private func releaseIdentifiers(_ identifiers: [IOPMAssertionID]) {
        for identifier in identifiers where identifier != 0 {
            IOPMAssertionRelease(identifier)
        }
    }

    private func ioHex(_ code: IOReturn) -> String {
        String(format: "0x%08x", code)
    }
    #endif

    private func installSignals() {
        #if canImport(Darwin)
        guard installSignalHandlers, !installedSignals else { return }
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        for signalNumber in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: DispatchQueue.global())
            source.setEventHandler { [weak self] in
                self?.cancel()
            }
            source.resume()
            signalSources.append(source)
        }
        installedSignals = true
        #endif
    }

    private func removeSignals() {
        #if canImport(Darwin)
        guard installedSignals else { return }
        for source in signalSources {
            source.cancel()
        }
        signalSources = []
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)
        installedSignals = false
        #endif
    }
}

private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var stopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func stop() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private func modeLabel(_ mode: HoldMode) -> String {
    switch mode {
    case .indefinite:
        return "indefinite"
    case .duration:
        return "duration"
    case .until:
        return "until"
    case .whileApp:
        return "whileApp"
    case .whileProcess:
        return "whileProcess"
    case .whilePID:
        return "whilePID"
    case .schedule:
        return "schedule"
    }
}
