import ArgumentParser
import Foundation

struct InstallApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-app",
        abstract: "Install an app manifest into a Mercantis SQLite database."
    )

    @Argument(help: "Path to the app manifest.json file.")
    var manifest: String

    @Option(name: .long, help: "Path to the Mercantis SQLite database file.")
    var dbPath: String

    @Flag(name: .long, help: "Validate only; do not write to the database.")
    var dryRun = false

    mutating func run() throws {
        let manifestURL = URL(fileURLWithPath: manifest)
        let data = try Data(contentsOf: manifestURL)

        let decoded = try JSONDecoder().decode(InstallableManifest.self, from: data)
        try validate(decoded)

        if dryRun {
            printSuccess("Manifest validation passed for \(decoded.id) (dry-run).")
            return
        }

        guard let rawManifest = String(data: data, encoding: .utf8) else {
            throw ValidationError("Failed to read manifest as UTF-8 JSON")
        }

        let db = try SQLiteDatabase(path: dbPath)
        try ensureAppsTable(in: db)

        let now = ISO8601DateFormatter().string(from: Date())
        try db.execute(
            "INSERT OR REPLACE INTO apps (id, title, version, installedAt, manifestJson) VALUES (?, ?, ?, ?, ?)",
            parameters: [decoded.id, decoded.title, decoded.version, now, rawManifest]
        )

        printSuccess("Installed app \(decoded.id)@\(decoded.version)")
    }

    private func validate(_ manifest: InstallableManifest) throws {
        guard !manifest.id.isEmpty else { throw ValidationError("Manifest id is required") }
        guard !manifest.title.isEmpty else { throw ValidationError("Manifest title is required") }
        guard !manifest.version.isEmpty else { throw ValidationError("Manifest version is required") }
        guard !manifest.minimumCoreVersion.isEmpty else { throw ValidationError("Manifest minimumCoreVersion is required") }

        guard isValidReverseDNS(manifest.id) else {
            throw ValidationError("Invalid id format. Expected reverse-DNS, e.g. app.mercantis.hub")
        }
        guard isValidSemver(manifest.version) else {
            throw ValidationError("Invalid version format. Expected semver, e.g. 0.1.0")
        }
        guard isValidSemver(manifest.minimumCoreVersion) else {
            throw ValidationError("Invalid minimumCoreVersion format. Expected semver, e.g. 1.0.0")
        }
    }

    private func ensureAppsTable(in db: SQLiteDatabase) throws {
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS apps (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                version TEXT NOT NULL,
                installedAt TEXT NOT NULL,
                manifestJson TEXT NOT NULL
            )
            """
        )

        let columns = Set(try db.query("PRAGMA table_info(apps)").compactMap { $0["name"] })
        if !columns.contains("title") {
            try db.execute("ALTER TABLE apps ADD COLUMN title TEXT")
        }
        if !columns.contains("manifestJson") {
            try db.execute("ALTER TABLE apps ADD COLUMN manifestJson TEXT")
        }

        let updatedColumns = Set(try db.query("PRAGMA table_info(apps)").compactMap { $0["name"] })
        let hasLegacyName = updatedColumns.contains("name")
        let hasLegacyPayload = updatedColumns.contains("payload")
        let hasTitle = updatedColumns.contains("title")
        let hasManifestJSON = updatedColumns.contains("manifestJson")

        if hasLegacyName && hasTitle {
            try db.execute("UPDATE apps SET title = name WHERE title IS NULL OR title = ''")
        }
        if hasLegacyPayload && hasManifestJSON {
            try db.execute("UPDATE apps SET manifestJson = payload WHERE manifestJson IS NULL OR manifestJson = ''")
        }
    }

    private struct InstallableManifest: Codable {
        let id: String
        let title: String
        let description: String?
        let publisher: String?
        let version: String
        let minimumCoreVersion: String
    }
}
