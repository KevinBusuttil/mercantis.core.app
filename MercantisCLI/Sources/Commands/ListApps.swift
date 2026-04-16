import ArgumentParser
import Foundation

struct ListApps: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-apps",
        abstract: "List installed apps from a Mercantis SQLite database."
    )

    enum OutputFormat: String, ExpressibleByArgument {
        case table
        case json
    }

    @Option(name: .long, help: "Path to the Mercantis SQLite database file.")
    var dbPath: String

    @Option(name: .long, help: "Output format: table or json.")
    var format: OutputFormat = .table

    mutating func run() throws {
        let db = try SQLiteDatabase(path: dbPath)

        guard db.tableExists("apps") else {
            printWarning("No apps table found in the database.")
            return
        }

        let rows = try db.query("SELECT * FROM apps")
        if rows.isEmpty {
            printWarning("No installed apps found.")
            return
        }

        switch format {
        case .json:
            let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted])
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        case .table:
            let headers = try tableHeaders(from: db, fallback: rows)
            let values = rows.map { row in
                headers.map { row[$0] ?? "" }
            }
            printTable(headers: headers, rows: values)
        }
    }

    private func tableHeaders(from db: SQLiteDatabase, fallback rows: [[String: String]]) throws -> [String] {
        let pragmaRows = try db.query("PRAGMA table_info(apps)")
        let ordered = pragmaRows.compactMap { $0["name"] }
        if !ordered.isEmpty {
            return ordered
        }

        return Array((rows.first ?? [:]).keys).sorted()
    }
}
