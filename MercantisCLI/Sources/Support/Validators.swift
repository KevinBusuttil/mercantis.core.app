import Foundation

func isValidReverseDNS(_ id: String) -> Bool {
    let pattern = "^[a-z][a-z0-9]*(\\.[a-z][a-z0-9]*){2,}$"
    return id.range(of: pattern, options: .regularExpression) != nil
}

func isValidSemver(_ version: String) -> Bool {
    let pattern = "^\\d+\\.\\d+\\.\\d+$"
    return version.range(of: pattern, options: .regularExpression) != nil
}

func slugify(_ text: String) -> String {
    let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let replaced = lowercased.replacingOccurrences(
        of: "[^a-z0-9]+",
        with: "_",
        options: .regularExpression
    )
    return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
}
