import Foundation

public enum KeepAwakeError: Error, Equatable, LocalizedError, CustomStringConvertible {
    case invalidDuration(String)
    case invalidTime(String)
    case invalidSchedule(String)
    case invalidArgument(String)
    case conflictingModes
    case policyDenied(String)
    case assertionFailed(String)
    case launchdFailed(String)
    case notRoot(String)
    case fileError(String)
    case processNotRunning(String)

    public var description: String {
        switch self {
        case .invalidDuration(let message),
             .invalidTime(let message),
             .invalidSchedule(let message),
             .invalidArgument(let message),
             .policyDenied(let message),
             .assertionFailed(let message),
             .launchdFailed(let message),
             .notRoot(let message),
             .fileError(let message),
             .processNotRunning(let message):
            return message
        case .conflictingModes:
            return "Choose only one mode. The modes are --indefinite, --duration, --until, --while-app, --while-process, --while-pid, and --schedule."
        }
    }

    public var errorDescription: String? { description }

    public var exitCode: Int32 {
        switch self {
        case .policyDenied:
            return 2
        case .assertionFailed:
            return 3
        case .launchdFailed, .notRoot:
            return 4
        case .processNotRunning:
            return 5
        default:
            return 1
        }
    }
}
