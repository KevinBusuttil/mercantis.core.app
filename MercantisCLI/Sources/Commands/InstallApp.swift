import ArgumentParser
import Foundation
import MercantisCore

/// CLI front-end for the same install pipeline the app uses (`AppInstaller`,
/// `MercantisDatabase`, `MetadataRegistry`, `SchemaValidator`). The CLI no
/// longer has its own raw-`sqlite3` install path; both surfaces share one
/// schema, one validation pass, and one set of side-effects (P2.3).
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

        // Pre-decode envelope checks: catch malformed id / version values
        // before they reach the engine. The engine validates DocType
        // structure; these regex checks cover the manifest envelope itself.
        try validateEnvelope(in: data)

        let dbURL = URL(fileURLWithPath: dbPath)
        let database = try MercantisDatabase(databaseURL: dbURL)
        let registry = MetadataRegistry(database: database)
        let installer = AppInstaller(
            database: database,
            schemaValidator: SchemaValidator(),
            registry: registry
        )

        if dryRun {
            let manifest = try installer.validate(manifestData: data)
            printSuccess("Manifest validation passed for \(manifest.id) (dry-run).")
            return
        }

        let manifest = try installer.install(manifestData: data)
        printSuccess("Installed app \(manifest.id)@\(manifest.version)")
    }

    private func validateEnvelope(in data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValidationError("Manifest must be a JSON object")
        }

        let id = (object["id"] as? String) ?? ""
        let version = (object["version"] as? String) ?? ""
        let minimumCoreVersion = (object["minimumCoreVersion"] as? String) ?? ""

        guard !id.isEmpty else { throw ValidationError("Manifest id is required") }
        guard !version.isEmpty else { throw ValidationError("Manifest version is required") }
        guard !minimumCoreVersion.isEmpty else { throw ValidationError("Manifest minimumCoreVersion is required") }

        guard isValidReverseDNS(id) else {
            throw ValidationError("Invalid id format. Expected reverse-DNS, e.g. app.mercantis.hub")
        }
        guard isValidSemver(version) else {
            throw ValidationError("Invalid version format. Expected semver, e.g. 0.1.0")
        }
        guard isValidSemver(minimumCoreVersion) else {
            throw ValidationError("Invalid minimumCoreVersion format. Expected semver, e.g. 1.0.0")
        }
    }
}
