import Foundation

public struct ManagedConfig: Equatable, Sendable {
    public var disabled: Bool
    public var allowIndefinite: Bool
    public var maximumDurationSeconds: Int?
    public var enforceSchedule: Bool
    public var defaultSchedule: String?
    public var lockAssertionProfile: Bool
    public var preventDisplaySleep: Bool?
    public var preventIdleSystemSleep: Bool?
    public var preventSystemSleep: Bool?
    public var preventDiskIdle: Bool?
    public var declareUserActivity: Bool?
    public var reason: String?
    public var lockReason: Bool
    public var allowUserAgent: Bool
    public var allowSystemDaemon: Bool
    public var backend: String?
    public var lockBackend: Bool

    public static let knownKeys: Set<String> = [
        "Disabled",
        "AllowIndefinite",
        "MaximumDurationSeconds",
        "EnforceSchedule",
        "DefaultSchedule",
        "LockAssertionProfile",
        "PreventDisplaySleep",
        "PreventIdleSystemSleep",
        "PreventSystemSleep",
        "PreventDiskIdle",
        "DeclareUserActivity",
        "Reason",
        "LockReason",
        "AllowUserAgent",
        "AllowSystemDaemon",
        "Backend",
        "LockBackend",
    ]

    public static let permissive = ManagedConfig(
        disabled: false,
        allowIndefinite: true,
        maximumDurationSeconds: nil,
        enforceSchedule: false,
        defaultSchedule: nil,
        lockAssertionProfile: false,
        preventDisplaySleep: nil,
        preventIdleSystemSleep: nil,
        preventSystemSleep: nil,
        preventDiskIdle: nil,
        declareUserActivity: nil,
        reason: nil,
        lockReason: false,
        allowUserAgent: true,
        allowSystemDaemon: true,
        backend: nil,
        lockBackend: false
    )

    public init(
        disabled: Bool,
        allowIndefinite: Bool,
        maximumDurationSeconds: Int?,
        enforceSchedule: Bool,
        defaultSchedule: String?,
        lockAssertionProfile: Bool,
        preventDisplaySleep: Bool?,
        preventIdleSystemSleep: Bool?,
        preventSystemSleep: Bool?,
        preventDiskIdle: Bool?,
        declareUserActivity: Bool?,
        reason: String?,
        lockReason: Bool,
        allowUserAgent: Bool,
        allowSystemDaemon: Bool,
        backend: String?,
        lockBackend: Bool
    ) {
        self.disabled = disabled
        self.allowIndefinite = allowIndefinite
        self.maximumDurationSeconds = maximumDurationSeconds
        self.enforceSchedule = enforceSchedule
        self.defaultSchedule = defaultSchedule
        self.lockAssertionProfile = lockAssertionProfile
        self.preventDisplaySleep = preventDisplaySleep
        self.preventIdleSystemSleep = preventIdleSystemSleep
        self.preventSystemSleep = preventSystemSleep
        self.preventDiskIdle = preventDiskIdle
        self.declareUserActivity = declareUserActivity
        self.reason = reason
        self.lockReason = lockReason
        self.allowUserAgent = allowUserAgent
        self.allowSystemDaemon = allowSystemDaemon
        self.backend = backend
        self.lockBackend = lockBackend
    }
}

public struct ConfigLayer: Equatable, Sendable {
    public var url: URL
    public var role: String

    public init(url: URL, role: String) {
        self.url = url
        self.role = role
    }
}

public struct ConfigLoadResult: Equatable, Sendable {
    public var config: ManagedConfig
    public var files: [String]
    public var warnings: [String]

    public init(config: ManagedConfig, files: [String], warnings: [String]) {
        self.config = config
        self.files = files
        self.warnings = warnings
    }
}

public enum ManagedConfigLoader {
    public static func defaultLayers(home: URL, userName: String, extra: URL?) -> [ConfigLayer] {
        var layers: [ConfigLayer] = [
            ConfigLayer(
                url: home.appendingPathComponent("Library").appendingPathComponent("Preferences").appendingPathComponent("\(KeepAwake.preferenceDomain).plist"),
                role: "user defaults"
            ),
        ]
        if let extra {
            layers.append(ConfigLayer(url: extra, role: "extra preferences"))
        }
        layers.append(
            ConfigLayer(
                url: URL(fileURLWithPath: "/Library/Managed Preferences/\(KeepAwake.preferenceDomain).plist"),
                role: "managed preferences"
            )
        )
        layers.append(
            ConfigLayer(
                url: URL(fileURLWithPath: "/Library/Managed Preferences/\(userName)/\(KeepAwake.preferenceDomain).plist"),
                role: "managed preferences for \(userName)"
            )
        )
        return layers
    }

    public static func loadDefault(extraPath: String? = nil) throws -> ConfigLoadResult {
        let account = currentAccount()
        let extra = extraPath.map { absoluteFileURL($0) }
        return try load(layers: defaultLayers(home: account.home, userName: account.name, extra: extra))
    }

    public static func load(layers: [ConfigLayer]) throws -> ConfigLoadResult {
        var merged: [String: Any] = [:]
        var origins: [String: String] = [:]
        var files: [String] = []
        var warnings: [String] = []
        let fileManager = FileManager.default
        for layer in layers {
            guard fileManager.fileExists(atPath: layer.url.path) else { continue }
            files.append("\(layer.role): \(layer.url.path)")
            let dictionary = try plistDictionary(at: layer.url)
            for key in dictionary.keys.sorted() where !ManagedConfig.knownKeys.contains(key) {
                warnings.append("Ignoring unknown key \(key) in \(layer.url.path).")
            }
            for (key, value) in dictionary where ManagedConfig.knownKeys.contains(key) {
                merged[key] = value
                origins[key] = layer.url.path
            }
        }
        let config = try parse(merged, origins: origins)
        return ConfigLoadResult(config: config, files: files, warnings: warnings)
    }

    public static func parse(_ dictionary: [String: Any], origins: [String: String] = [:]) throws -> ManagedConfig {
        var config = ManagedConfig.permissive
        func source(_ key: String) -> String {
            origins[key] ?? "preferences"
        }
        if dictionary.keys.contains("Disabled") {
            config.disabled = try requiredBool(dictionary, key: "Disabled", source: source("Disabled"))
        }
        if dictionary.keys.contains("AllowIndefinite") {
            config.allowIndefinite = try requiredBool(dictionary, key: "AllowIndefinite", source: source("AllowIndefinite"))
        }
        if dictionary.keys.contains("MaximumDurationSeconds") {
            let seconds = try requiredInt(dictionary, key: "MaximumDurationSeconds", source: source("MaximumDurationSeconds"))
            guard seconds > 0 else {
                throw KeepAwakeError.policyDenied(
                    "MaximumDurationSeconds in \(source("MaximumDurationSeconds")) must be greater than zero."
                )
            }
            config.maximumDurationSeconds = seconds
        }
        if dictionary.keys.contains("EnforceSchedule") {
            config.enforceSchedule = try requiredBool(dictionary, key: "EnforceSchedule", source: source("EnforceSchedule"))
        }
        if dictionary.keys.contains("DefaultSchedule") {
            config.defaultSchedule = try requiredString(dictionary, key: "DefaultSchedule", source: source("DefaultSchedule"))
        }
        if dictionary.keys.contains("LockAssertionProfile") {
            config.lockAssertionProfile = try requiredBool(dictionary, key: "LockAssertionProfile", source: source("LockAssertionProfile"))
        }
        if dictionary.keys.contains("PreventDisplaySleep") {
            config.preventDisplaySleep = try requiredBool(dictionary, key: "PreventDisplaySleep", source: source("PreventDisplaySleep"))
        }
        if dictionary.keys.contains("PreventIdleSystemSleep") {
            config.preventIdleSystemSleep = try requiredBool(dictionary, key: "PreventIdleSystemSleep", source: source("PreventIdleSystemSleep"))
        }
        if dictionary.keys.contains("PreventSystemSleep") {
            config.preventSystemSleep = try requiredBool(dictionary, key: "PreventSystemSleep", source: source("PreventSystemSleep"))
        }
        if dictionary.keys.contains("PreventDiskIdle") {
            config.preventDiskIdle = try requiredBool(dictionary, key: "PreventDiskIdle", source: source("PreventDiskIdle"))
        }
        if dictionary.keys.contains("DeclareUserActivity") {
            config.declareUserActivity = try requiredBool(dictionary, key: "DeclareUserActivity", source: source("DeclareUserActivity"))
        }
        if dictionary.keys.contains("Reason") {
            config.reason = try requiredString(dictionary, key: "Reason", source: source("Reason"))
        }
        if dictionary.keys.contains("LockReason") {
            config.lockReason = try requiredBool(dictionary, key: "LockReason", source: source("LockReason"))
        }
        if dictionary.keys.contains("AllowUserAgent") {
            config.allowUserAgent = try requiredBool(dictionary, key: "AllowUserAgent", source: source("AllowUserAgent"))
        }
        if dictionary.keys.contains("AllowSystemDaemon") {
            config.allowSystemDaemon = try requiredBool(dictionary, key: "AllowSystemDaemon", source: source("AllowSystemDaemon"))
        }
        if dictionary.keys.contains("Backend") {
            config.backend = try requiredString(dictionary, key: "Backend", source: source("Backend"))
        }
        if dictionary.keys.contains("LockBackend") {
            config.lockBackend = try requiredBool(dictionary, key: "LockBackend", source: source("LockBackend"))
        }
        return config
    }

    public static func lines(for result: ConfigLoadResult) -> [String] {
        let config = result.config
        var lines = [
            "Domain: \(KeepAwake.preferenceDomain)",
            "Disabled: \(config.disabled)",
            "Allow indefinite: \(config.allowIndefinite)",
            "Maximum duration: \(config.maximumDurationSeconds.map { formatDuration(TimeInterval($0)) } ?? "none")",
            "Enforce schedule: \(config.enforceSchedule)",
            "Default schedule: \(config.defaultSchedule ?? "none")",
            "Lock assertion profile: \(config.lockAssertionProfile)",
            "Prevent display sleep: \(optionalBool(config.preventDisplaySleep))",
            "Prevent idle system sleep: \(optionalBool(config.preventIdleSystemSleep))",
            "Prevent system sleep: \(optionalBool(config.preventSystemSleep))",
            "Prevent disk idle: \(optionalBool(config.preventDiskIdle))",
            "Declare user activity: \(optionalBool(config.declareUserActivity))",
            "Reason: \(config.reason ?? "none")",
            "Lock reason: \(config.lockReason)",
            "Allow user agent: \(config.allowUserAgent)",
            "Allow system daemon: \(config.allowSystemDaemon)",
            "Backend: \(config.backend ?? "none")",
            "Lock backend: \(config.lockBackend)",
        ]
        if result.files.isEmpty {
            lines.append("Files: none")
        } else {
            lines.append("Files:")
            lines.append(contentsOf: result.files.map { "  \($0)" })
        }
        if !result.warnings.isEmpty {
            lines.append("Warnings:")
            lines.append(contentsOf: result.warnings.map { "  \($0)" })
        }
        return lines
    }

    public static func jsonObject(for result: ConfigLoadResult) -> [String: Any] {
        let config = result.config
        return [
            "domain": KeepAwake.preferenceDomain,
            "disabled": config.disabled,
            "allowIndefinite": config.allowIndefinite,
            "maximumDurationSeconds": config.maximumDurationSeconds ?? NSNull(),
            "enforceSchedule": config.enforceSchedule,
            "defaultSchedule": config.defaultSchedule ?? NSNull(),
            "lockAssertionProfile": config.lockAssertionProfile,
            "preventDisplaySleep": config.preventDisplaySleep ?? NSNull(),
            "preventIdleSystemSleep": config.preventIdleSystemSleep ?? NSNull(),
            "preventSystemSleep": config.preventSystemSleep ?? NSNull(),
            "preventDiskIdle": config.preventDiskIdle ?? NSNull(),
            "declareUserActivity": config.declareUserActivity ?? NSNull(),
            "reason": config.reason ?? NSNull(),
            "lockReason": config.lockReason,
            "allowUserAgent": config.allowUserAgent,
            "allowSystemDaemon": config.allowSystemDaemon,
            "backend": config.backend ?? NSNull(),
            "lockBackend": config.lockBackend,
            "files": result.files,
            "warnings": result.warnings,
        ]
    }
}

private func optionalBool(_ value: Bool?) -> String {
    guard let value else { return "unset" }
    return value ? "true" : "false"
}

func plistDictionary(at url: URL) throws -> [String: Any] {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw KeepAwakeError.fileError("Could not read \(url.path): \(error.localizedDescription)")
    }
    let object: Any
    do {
        object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    } catch {
        throw KeepAwakeError.fileError("Could not parse property list \(url.path): \(error.localizedDescription)")
    }
    guard let dictionary = object as? [String: Any] else {
        throw KeepAwakeError.fileError("Property list \(url.path) is not a dictionary.")
    }
    return dictionary
}

private func requiredBool(_ dictionary: [String: Any], key: String, source: String) throws -> Bool {
    guard let value = boolValue(dictionary[key]) else {
        throw KeepAwakeError.policyDenied("\(key) in \(source) must be a boolean.")
    }
    return value
}

private func requiredInt(_ dictionary: [String: Any], key: String, source: String) throws -> Int {
    guard let value = intValue(dictionary[key]) else {
        throw KeepAwakeError.policyDenied("\(key) in \(source) must be an integer.")
    }
    return value
}

private func requiredString(_ dictionary: [String: Any], key: String, source: String) throws -> String {
    guard let value = dictionary[key] as? String else {
        throw KeepAwakeError.policyDenied("\(key) in \(source) must be a string.")
    }
    return value
}

func boolValue(_ value: Any?) -> Bool? {
    if let bool = value as? Bool {
        return bool
    }
    if let string = value as? String {
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }
    if let number = value as? NSNumber {
        if String(cString: number.objCType) == "c" || String(cString: number.objCType) == "B" {
            return number.boolValue
        }
    }
    return nil
}

func intValue(_ value: Any?) -> Int? {
    if value is Bool {
        return nil
    }
    if let int = value as? Int {
        return int
    }
    if let number = value as? NSNumber {
        return number.intValue
    }
    if let string = value as? String {
        return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
}
