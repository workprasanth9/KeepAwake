import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct Account: Equatable, Sendable {
    public var name: String
    public var uid: uid_t
    public var gid: gid_t
    public var home: URL

    public init(name: String, uid: uid_t, gid: gid_t, home: URL) {
        self.name = name
        self.uid = uid
        self.gid = gid
        self.home = home
    }
}

public func currentAccount() -> Account {
    let uid = getuid()
    if let pointer = getpwuid(uid) {
        let record = pointer.pointee
        return Account(
            name: String(cString: record.pw_name),
            uid: uid,
            gid: record.pw_gid,
            home: URL(fileURLWithPath: String(cString: record.pw_dir), isDirectory: true)
        )
    }
    return Account(
        name: NSUserName(),
        uid: uid,
        gid: getgid(),
        home: FileManager.default.homeDirectoryForCurrentUser
    )
}

public func account(named name: String) -> Account? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("/") else { return nil }
    return trimmed.withCString { pointer in
        guard let recordPointer = getpwnam(pointer) else { return nil }
        let record = recordPointer.pointee
        return Account(
            name: String(cString: record.pw_name),
            uid: record.pw_uid,
            gid: record.pw_gid,
            home: URL(fileURLWithPath: String(cString: record.pw_dir), isDirectory: true)
        )
    }
}

public func isRootUser() -> Bool {
    geteuid() == 0
}

public enum LaunchdScope: String, Equatable, Sendable {
    case agent
    case daemon
}

public struct InstallLocations: Equatable, Sendable {
    public var plistDirectory: URL
    public var logDirectory: URL
    public var binaryDirectory: URL
    public var domain: String
    public var uid: uid_t
    public var gid: gid_t

    public init(
        plistDirectory: URL,
        logDirectory: URL,
        binaryDirectory: URL,
        domain: String,
        uid: uid_t,
        gid: gid_t
    ) {
        self.plistDirectory = plistDirectory
        self.logDirectory = logDirectory
        self.binaryDirectory = binaryDirectory
        self.domain = domain
        self.uid = uid
        self.gid = gid
    }

    public var sessionDirectory: URL {
        binaryDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    public func plistURL(label: String) -> URL {
        plistDirectory.appendingPathComponent("\(label).plist")
    }

    public var copiedBinaryURL: URL {
        binaryDirectory.appendingPathComponent("keepawake")
    }
}

public enum InstallLayout {
    public static func make(scope: LaunchdScope, account: Account) -> InstallLocations {
        switch scope {
        case .agent:
            return InstallLocations(
                plistDirectory: account.home
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("LaunchAgents", isDirectory: true),
                logDirectory: account.home
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Logs", isDirectory: true)
                    .appendingPathComponent("KeepAwake", isDirectory: true),
                binaryDirectory: account.home
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("KeepAwake", isDirectory: true),
                domain: "gui/\(account.uid)",
                uid: account.uid,
                gid: account.gid
            )
        case .daemon:
            return InstallLocations(
                plistDirectory: URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true),
                logDirectory: URL(fileURLWithPath: "/Library/Logs/KeepAwake", isDirectory: true),
                binaryDirectory: URL(fileURLWithPath: "/Library/Application Support/KeepAwake", isDirectory: true),
                domain: "system",
                uid: 0,
                gid: 0
            )
        }
    }
}
