import Foundation

func printSuccess(_ message: String) {
    print("✅ \(message)")
}

func printError(_ message: String) {
    let output = "❌ \(message)\n"
    if let data = output.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func printWarning(_ message: String) {
    print("⚠️ \(message)")
}

func printTable(headers: [String], rows: [[String]]) {
    guard !headers.isEmpty else { return }

    var widths = headers.map { $0.count }
    for row in rows {
        for (index, value) in row.enumerated() where index < widths.count {
            widths[index] = max(widths[index], value.count)
        }
    }

    let headerLine = zip(headers, widths)
        .map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
        .joined(separator: "  ")

    let separatorLine = widths
        .map { String(repeating: "-", count: $0) }
        .joined(separator: "  ")

    print(headerLine)
    print(separatorLine)

    for row in rows {
        let line = zip(row, widths)
            .map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
        print(line)
    }
}

@discardableResult
func prompt(_ text: String, defaultValue: String? = nil) -> String {
    if let defaultValue {
        print("\(text) [\(defaultValue)]: ", terminator: "")
    } else {
        print("\(text): ", terminator: "")
    }

    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
        return defaultValue ?? ""
    }
    return input
}
