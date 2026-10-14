import Foundation

public struct LaunchdSpec: Equatable, Sendable {
    public var label: String
    public var programArguments: [String]
    public var runAtLoad: Bool
    public var keepAlive: Bool
    public var limitLoadToSessionType: String?
    public var processType: String?
    public var throttleInterval: Int
    public var standardOutPath: String
    public var standardErrorPath: String

    public init(
        label: String,
        programArguments: [String],
        runAtLoad: Bool,
        keepAlive: Bool,
        limitLoadToSessionType: String?,
        processType: String?,
        throttleInterval: Int,
        standardOutPath: String,
        standardErrorPath: String
    ) {
        self.label = label
        self.programArguments = programArguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.limitLoadToSessionType = limitLoadToSessionType
        self.processType = processType
        self.throttleInterval = throttleInterval
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
    }
}

public enum PlistXML {
    public static func renderLaunchd(_ spec: LaunchdSpec) -> String {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">")
        lines.append("<plist version=\"1.0\">")
        lines.append("<dict>")
        lines.append(contentsOf: element("Label", .string(spec.label), indent: 1))
        lines.append(contentsOf: element("ProgramArguments", .array(spec.programArguments.map(PlistScalar.string)), indent: 1))
        lines.append(contentsOf: element("RunAtLoad", .bool(spec.runAtLoad), indent: 1))
        lines.append(contentsOf: element("KeepAlive", .bool(spec.keepAlive), indent: 1))
        if let processType = spec.processType {
            lines.append(contentsOf: element("ProcessType", .string(processType), indent: 1))
        }
        if let session = spec.limitLoadToSessionType {
            lines.append(contentsOf: element("LimitLoadToSessionType", .string(session), indent: 1))
        }
        lines.append(contentsOf: element("ThrottleInterval", .int(spec.throttleInterval), indent: 1))
        lines.append(contentsOf: element("StandardOutPath", .string(spec.standardOutPath), indent: 1))
        lines.append(contentsOf: element("StandardErrorPath", .string(spec.standardErrorPath), indent: 1))
        lines.append("</dict>")
        lines.append("</plist>")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

private enum PlistScalar {
    case string(String)
    case bool(Bool)
    case int(Int)
    case array([PlistScalar])
}

private func element(_ key: String, _ value: PlistScalar, indent: Int) -> [String] {
    let pad = String(repeating: "  ", count: indent)
    var lines = ["\(pad)<key>\(xmlEscape(key))</key>"]
    lines.append(contentsOf: render(value, indent: indent))
    return lines
}

private func render(_ value: PlistScalar, indent: Int) -> [String] {
    let pad = String(repeating: "  ", count: indent)
    switch value {
    case .string(let string):
        return ["\(pad)<string>\(xmlEscape(string))</string>"]
    case .bool(let bool):
        return ["\(pad)<\(bool ? "true" : "false")/>"]
    case .int(let int):
        return ["\(pad)<integer>\(int)</integer>"]
    case .array(let values):
        var lines = ["\(pad)<array>"]
        for item in values {
            lines.append(contentsOf: render(item, indent: indent + 1))
        }
        lines.append("\(pad)</array>")
        return lines
    }
}
