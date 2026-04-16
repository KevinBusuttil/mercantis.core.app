import ArgumentParser
import Foundation

struct Migrate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Run pending Mercantis patches against a SQLite database."
    )

    @Option(name: .long, help: "Path to the Mercantis SQLite database file.")
    var dbPath: String

    @Option(name: .long, help: "Directory containing patches.json and patch descriptor files.")
    var patchesDir: String = "./patches"

    @Flag(name: .long, help: "Skip failing patches instead of aborting.")
    var skipFailing = false

    @Flag(name: .long, help: "Print what would run without executing SQL.")
    var dryRun = false

    mutating func run() throws {
        let db = try SQLiteDatabase(path: dbPath)

        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS patch_log (
                patch TEXT PRIMARY KEY,
                executedAt TEXT NOT NULL,
                skipped INTEGER NOT NULL DEFAULT 0
            )
            """
        )

        let indexURL = URL(fileURLWithPath: patchesDir).appendingPathComponent("patches.json")
        let indexData = try Data(contentsOf: indexURL)
        let index = try JSONDecoder().decode(PatchIndex.self, from: indexData)

        var ran = 0
        var alreadyApplied = 0
        var failed = 0
        var wouldRun = 0

        for patchName in index.patches {
            let exists = try !db.query(
                "SELECT patch FROM patch_log WHERE patch = ? LIMIT 1",
                parameters: [patchName]
            ).isEmpty

            if exists {
                alreadyApplied += 1
                continue
            }

            let descriptorURL = URL(fileURLWithPath: patchesDir).appendingPathComponent("\(patchName).json")
            let descriptorData = try Data(contentsOf: descriptorURL)
            let descriptor = try JSONDecoder().decode(PatchDescriptor.self, from: descriptorData)

            if dryRun {
                wouldRun += 1
                printWarning("[dry-run] Would run patch: \(descriptor.name)")
                for statement in descriptor.sql {
                    print(statement)
                }
                continue
            }

            do {
                try db.execute("BEGIN TRANSACTION")
                for statement in descriptor.sql {
                    try db.execute(statement)
                }
                try db.execute("COMMIT")

                let now = ISO8601DateFormatter().string(from: Date())
                try db.execute(
                    "INSERT INTO patch_log (patch, executedAt, skipped) VALUES (?, ?, 0)",
                    parameters: [patchName, now]
                )
                ran += 1
            } catch {
                _ = try? db.execute("ROLLBACK")
                failed += 1

                if skipFailing {
                    let now = ISO8601DateFormatter().string(from: Date())
                    try db.execute(
                        "INSERT OR REPLACE INTO patch_log (patch, executedAt, skipped) VALUES (?, ?, 1)",
                        parameters: [patchName, now]
                    )
                    printWarning("Skipped failing patch: \(patchName) — \(error.localizedDescription)")
                    continue
                }

                throw error
            }
        }

        if dryRun {
            printSuccess("Dry run complete. Would run: \(wouldRun), already applied: \(alreadyApplied)")
            return
        }

        printSuccess("Migration complete. Ran: \(ran), already applied: \(alreadyApplied), failed: \(failed)")
    }

    private struct PatchIndex: Codable {
        let patches: [String]
    }

    private struct PatchDescriptor: Codable {
        let name: String
        let description: String
        let sql: [String]
    }
}
