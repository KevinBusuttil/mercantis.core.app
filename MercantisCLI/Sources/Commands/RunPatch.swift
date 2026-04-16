import ArgumentParser
import Foundation

struct RunPatch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-patch",
        abstract: "Run a single named patch against a Mercantis database."
    )

    @Argument(help: "Patch name, e.g. 001_initial_seed")
    var patch: String

    @Option(name: .long, help: "Path to the Mercantis SQLite database file.")
    var dbPath: String

    @Option(name: .long, help: "Directory containing patch descriptors.")
    var patchesDir: String = "./patches"

    @Flag(name: .long, help: "Run even if the patch is already logged in patch_log.")
    var force = false

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

        let alreadyApplied = try !db.query(
            "SELECT patch FROM patch_log WHERE patch = ? LIMIT 1",
            parameters: [patch]
        ).isEmpty

        if alreadyApplied && !force {
            printWarning("Patch \(patch) is already applied. Use --force to run it again.")
            return
        }

        let descriptorURL = URL(fileURLWithPath: patchesDir).appendingPathComponent("\(patch).json")
        let descriptorData = try Data(contentsOf: descriptorURL)
        let descriptor = try JSONDecoder().decode(PatchDescriptor.self, from: descriptorData)

        try db.execute("BEGIN TRANSACTION")
        do {
            for statement in descriptor.sql {
                try db.execute(statement)
            }
            try db.execute("COMMIT")
        } catch {
            _ = try? db.execute("ROLLBACK")
            throw error
        }

        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute(
            "INSERT OR REPLACE INTO patch_log (patch, executedAt, skipped) VALUES (?, ?, 0)",
            parameters: [patch, now]
        )

        printSuccess("Patch \(patch) executed successfully.")
    }

    private struct PatchDescriptor: Codable {
        let name: String
        let description: String
        let sql: [String]
    }
}
