import Foundation

public func caffeinateArguments(for request: ResolvedRequest, now: Date) -> [String] {
    var flags = ""
    if request.profile.preventDisplaySleep { flags.append("d") }
    if request.profile.preventIdleSystemSleep { flags.append("i") }
    if request.profile.preventDiskIdle { flags.append("m") }
    if request.profile.preventSystemSleep { flags.append("s") }
    if request.profile.declareUserActivity { flags.append("u") }
    var arguments: [String] = []
    if !flags.isEmpty {
        arguments.append("-\(flags)")
    }
    switch request.mode {
    case .duration(let interval):
        arguments.append(contentsOf: ["-t", String(max(1, Int(interval.rounded(.up))))])
    case .until(let date):
        let seconds = max(1, Int(date.timeIntervalSince(now).rounded(.up)))
        arguments.append(contentsOf: ["-t", String(seconds)])
    case .whilePID(let pid):
        arguments.append(contentsOf: ["-w", String(pid)])
    case .indefinite, .whileApp, .whileProcess, .schedule:
        break
    }
    return arguments
}
