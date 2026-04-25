import ArgumentParser
import Foundation
import GRDB
import MercantisCore

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
        let dbURL = URL(fileURLWithPath: dbPath)
        let database = try MercantisDatabase(databaseURL: dbURL)

        let rows: [[String: String]] = try database.read { db in
            let fetched = try Row.fetchAll(
                db,
                sql: "SELECT id, name, version, installedAt FROM apps ORDER BY id"
            )
            return fetched.map { row in
                [
                    "id": row["id"] as String? ?? "",
                    "name": row["name"] as String? ?? "",
                    "version": row["version"] as String? ?? "",
                    "installedAt": row["installedAt"] as String? ?? ""
                ]
            }
        }

        if rows.isEmpty {
            printWarning("No installed apps found.")
            return
        }

        switch format {
        case .json:
            let data = try JSONSerialization.data(
                withJSONObject: rows,
                options: [.prettyPrinted, .sortedKeys]
            )
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        case .table:
            let headers = ["id", "name", "version", "installedAt"]
            let values = rows.map { row in headers.map { row[$0] ?? "" } }
            printTable(headers: headers, rows: values)
        }
    }
}
