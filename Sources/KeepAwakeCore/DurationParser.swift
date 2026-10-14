import Foundation

public func parseDuration(_ raw: String) throws -> TimeInterval {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !text.isEmpty else {
        throw KeepAwakeError.invalidDuration("Duration is empty. Use values such as 90s, 45m, 2h, or 1h30m.")
    }
    if let seconds = Double(text), !text.contains(where: { $0.isLetter }) {
        return try validatedDuration(seconds, original: raw)
    }

    var total = 0.0
    var index = text.startIndex
    var parts = 0
    while index < text.endIndex {
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        if index == text.endIndex {
            break
        }
        let numberStart = index
        var sawDigit = false
        var sawDot = false
        while index < text.endIndex {
            let character = text[index]
            if character.isNumber {
                sawDigit = true
                index = text.index(after: index)
                continue
            }
            if character == ".", !sawDot {
                sawDot = true
                index = text.index(after: index)
                continue
            }
            break
        }
        guard sawDigit, let value = Double(text[numberStart..<index]) else {
            throw KeepAwakeError.invalidDuration(
                "Invalid duration \"\(raw)\". Use values such as 90s, 45m, 2h, or 1h30m."
            )
        }
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        let unitStart = index
        while index < text.endIndex, text[index].isLetter {
            index = text.index(after: index)
        }
        let unit = String(text[unitStart..<index])
        guard let multiplier = durationUnitMultiplier(unit) else {
            let rendered = unit.isEmpty ? "(missing)" : unit
            throw KeepAwakeError.invalidDuration(
                "Unknown duration unit \"\(rendered)\" in \"\(raw)\". Use s, m, h, or d."
            )
        }
        total += value * multiplier
        parts += 1
    }
    guard parts > 0 else {
        throw KeepAwakeError.invalidDuration(
            "Invalid duration \"\(raw)\". Use values such as 90s, 45m, 2h, or 1h30m."
        )
    }
    return try validatedDuration(total.rounded(), original: raw)
}

private func durationUnitMultiplier(_ unit: String) -> Double? {
    switch unit {
    case "s", "sec", "secs", "second", "seconds":
        return 1
    case "m", "min", "mins", "minute", "minutes":
        return 60
    case "h", "hr", "hrs", "hour", "hours":
        return 3_600
    case "d", "day", "days":
        return 86_400
    default:
        return nil
    }
}

private func validatedDuration(_ seconds: Double, original: String) throws -> TimeInterval {
    guard seconds.isFinite, seconds > 0 else {
        throw KeepAwakeError.invalidDuration("Duration \"\(original)\" must be greater than zero.")
    }
    guard seconds <= 366 * 86_400 else {
        throw KeepAwakeError.invalidDuration("Duration \"\(original)\" is longer than 366 days.")
    }
    return seconds
}
