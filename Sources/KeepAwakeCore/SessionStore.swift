import Foundation

public struct SessionState: Codable, Equatable, Sendable {
    public var pid: Int32
    public var mode: String
    public var summary: String
    public var reason: String
    public var profile: [String]
    public var backend: String
    public var startedAt: Date
    public var endsAt: Date?

    public init(
        pid: Int32,
        mode: String,
        summary: String,
        reason: String,
        profile: [String],
        backend: String,
        startedAt: Date,
        endsAt: Date?
    ) {
        self.pid = pid
        self.mode = mode
        self.summary = summary
        self.reason = reason
        self.profile = profile
        self.backend = backend
        self.startedAt = startedAt
        self.endsAt = endsAt
    }
}

public enum SessionStore {
    public static func directoryForCurrentProcess() -> URL {
        if isRootUser() {
            return URL(fileURLWithPath: "/Library/Application Support/KeepAwake/sessions", isDirectory: true)
        }
        return currentAccount().home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("KeepAwake", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public static func write(_ state: SessionState, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let url = directory.appendingPathComponent("\(state.pid).json")
        try data.write(to: url, options: .atomic)
    }

    public static func remove(pid: Int32, directory: URL) {
        let url = directory.appendingPathComponent("\(pid).json")
        try? FileManager.default.removeItem(at: url)
    }

    public static func loadAll(directories: [URL], removeStale: Bool) -> [SessionState] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var states: [SessionState] = []
        let fileManager = FileManager.default
        for directory in directories {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else { continue }
            for url in urls where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let state = try? decoder.decode(SessionState.self, from: data) else {
                    continue
                }
                if !pidExists(state.pid) {
                    if removeStale {
                        try? fileManager.removeItem(at: url)
                    }
                    continue
                }
                states.append(state)
            }
        }
        var seen = Set<Int32>()
        return states.filter { seen.insert($0.pid).inserted }.sorted { $0.pid < $1.pid }
    }
}
