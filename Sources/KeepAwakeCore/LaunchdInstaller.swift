import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct InstallRequest: Equatable, Sendable {
    public var label: String
    public var scope: LaunchdScope
    public var programArguments: [String]
    public var keepAlive: Bool
    public var binarySource: URL
    public var copyBinary: Bool

    public init(
        label: String,
        scope: LaunchdScope,
        programArguments: [String],
        keepAlive: Bool,
        binarySource: URL,
        copyBinary: Bool
    ) {
        self.label = label
        self.scope = scope
        self.programArguments = programArguments
        self.keepAlive = keepAlive
        self.binarySource = binarySource
        self.copyBinary = copyBinary
    }
}

public struct InstalledJob: Equatable, Sendable {
    public var label: String
    public var scope: LaunchdScope
    public var plistPath: String
    public var binaryPath: String
    public var domain: String
    public var programArguments: [String]
    public var plist: String

    public init(
        label: String,
        scope: LaunchdScope,
        plistPath: String,
        binaryPath: String,
        domain: String,
        programArguments: [String],
        plist: String
    ) {
        self.label = label
        self.scope = scope
        self.plistPath = plistPath
        self.binaryPath = binaryPath
        self.domain = domain
        self.programArguments = programArguments
        self.plist = plist
    }
}

public struct UninstallReport: Equatable, Sendable {
    public var label: String
    public var plistRemoved: Bool
    public var binaryRemoved: Bool
    public var plistPath: String

    public init(label: String, plistRemoved: Bool, binaryRemoved: Bool, plistPath: String) {
        self.label = label
        self.plistRemoved = plistRemoved
        self.binaryRemoved = binaryRemoved
        self.plistPath = plistPath
    }
}

public struct LaunchdInstaller {
    public var launchctl: LaunchctlClient
    public var adjustOwnership: Bool
    public var fileManager: FileManager

    public init(launchctl: LaunchctlClient, adjustOwnership: Bool, fileManager: FileManager = .default) {
        self.launchctl = launchctl
        self.adjustOwnership = adjustOwnership
        self.fileManager = fileManager
    }

    public func install(request: InstallRequest, locations: InstallLocations) throws -> InstalledJob {
        guard request.programArguments.count >= 2 else {
            throw KeepAwakeError.invalidArgument("The launchd job needs a binary path and the start command.")
        }
        let source = request.binarySource.standardizedFileURL
        guard fileManager.isExecutableFile(atPath: source.path) else {
            throw KeepAwakeError.fileError("Binary is missing or is not executable: \(source.path)")
        }
        try createDirectory(locations.plistDirectory)
        try createDirectory(locations.logDirectory)
        try createDirectory(locations.binaryDirectory)

        let binaryURL: URL
        if request.copyBinary {
            binaryURL = locations.copiedBinaryURL
            if source.path != binaryURL.path {
                if fileManager.fileExists(atPath: binaryURL.path) {
                    try fileManager.removeItem(at: binaryURL)
                }
                try fileManager.copyItem(at: source, to: binaryURL)
            }
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
            try applyOwnership(binaryURL, locations: locations)
        } else {
            binaryURL = source
        }

        var arguments = request.programArguments
        arguments[0] = binaryURL.path
        let spec = LaunchdSpec(
            label: request.label,
            programArguments: arguments,
            runAtLoad: true,
            keepAlive: request.keepAlive,
            limitLoadToSessionType: request.scope == .agent ? "Aqua" : nil,
            processType: request.scope == .agent ? "Interactive" : nil,
            throttleInterval: 10,
            standardOutPath: locations.logDirectory.appendingPathComponent("keepawake.out.log").path,
            standardErrorPath: locations.logDirectory.appendingPathComponent("keepawake.err.log").path
        )
        let xml = PlistXML.renderLaunchd(spec)
        let plistURL = locations.plistURL(label: request.label)
        do {
            try xml.write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            throw KeepAwakeError.fileError("Could not write \(plistURL.path): \(error.localizedDescription)")
        }
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)
        try applyOwnership(plistURL, locations: locations)
        try bootstrap(label: request.label, domain: locations.domain, plistPath: plistURL)
        return InstalledJob(
            label: request.label,
            scope: request.scope,
            plistPath: plistURL.path,
            binaryPath: binaryURL.path,
            domain: locations.domain,
            programArguments: arguments,
            plist: xml
        )
    }

    public func uninstall(
        label: String,
        locations: InstallLocations,
        purgeBinary: Bool
    ) throws -> UninstallReport {
        let plistURL = locations.plistURL(label: label)
        try bootout(label: label, domain: locations.domain)
        var removedPlist = false
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
            removedPlist = true
        }
        var removedBinary = false
        if purgeBinary {
            let binary = locations.copiedBinaryURL
            if fileManager.fileExists(atPath: binary.path) {
                try fileManager.removeItem(at: binary)
                removedBinary = true
            }
        }
        return UninstallReport(
            label: label,
            plistRemoved: removedPlist,
            binaryRemoved: removedBinary,
            plistPath: plistURL.path
        )
    }

    public func bootout(label: String, domain: String) throws {
        let result = launchctl.run(["bootout", "\(domain)/\(label)"])
        if result.succeeded || isBenignLaunchctlFailure(result) {
            return
        }
        throw KeepAwakeError.launchdFailed(launchctlMessage("bootout", result))
    }

    public func bootstrap(label: String, domain: String, plistPath: URL) throws {
        _ = launchctl.run(["enable", "\(domain)/\(label)"])
        _ = bootoutIgnoringMissing(label: label, domain: domain)
        let result = launchctl.run(["bootstrap", domain, plistPath.path])
        if result.succeeded || isAlreadyLoaded(result) {
            return
        }
        throw KeepAwakeError.launchdFailed(launchctlMessage("bootstrap", result))
    }

    private func bootoutIgnoringMissing(label: String, domain: String) -> CommandResult {
        let result = launchctl.run(["bootout", "\(domain)/\(label)"])
        return result
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw KeepAwakeError.fileError("Could not create \(url.path): \(error.localizedDescription)")
        }
    }

    private func applyOwnership(_ url: URL, locations: InstallLocations) throws {
        guard adjustOwnership else { return }
        let status = url.path.withCString { pointer in
            chown(pointer, locations.uid, locations.gid)
        }
        if status != 0 {
            throw KeepAwakeError.fileError("Could not change ownership of \(url.path) (errno \(errno)).")
        }
    }
}

func isBenignLaunchctlFailure(_ result: CommandResult) -> Bool {
    let text = (result.stdout + "\n" + result.stderr).lowercased()
    return text.contains("no such process")
        || text.contains("could not find")
        || text.contains("not found")
}

func isAlreadyLoaded(_ result: CommandResult) -> Bool {
    let text = (result.stdout + "\n" + result.stderr).lowercased()
    return text.contains("already bootstrapped")
        || text.contains("service already loaded")
        || text.contains("already loaded")
}

func launchctlMessage(_ action: String, _ result: CommandResult) -> String {
    let detail = [result.stderr, result.stdout]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? "exit \(result.status)"
    return "launchctl \(action) failed: \(detail)"
}

public func validateLaunchdLabel(_ label: String) throws {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
    guard !label.isEmpty, label.unicodeScalars.allSatisfy({ allowed.contains($0) }), !label.hasPrefix("."), !label.hasSuffix(".") else {
        throw KeepAwakeError.invalidArgument(
            "Label \"\(label)\" must be a launchd label such as com.keepawake.agent."
        )
    }
}
