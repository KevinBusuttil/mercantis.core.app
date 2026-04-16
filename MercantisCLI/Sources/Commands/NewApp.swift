import ArgumentParser
import Foundation

struct NewApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new-app",
        abstract: "Interactively scaffold a new Mercantis app manifest."
    )

    mutating func run() throws {
        var appID = ""
        repeat {
            appID = prompt("App ID (reverse-DNS, e.g. app.mercantis.hub)")
            if !isValidReverseDNS(appID) {
                printError("Invalid app ID format. Expected reverse-DNS like app.mercantis.hub")
            }
        } while !isValidReverseDNS(appID)

        let title = prompt("App Title")
        let description = prompt("App Description")
        let publisher = prompt("App Publisher")
        let version = prompt("App Version", defaultValue: "0.1.0")
        let minimumCoreVersion = prompt("Minimum Core Version", defaultValue: "1.0.0")
        let outputDirectory = prompt("Output directory", defaultValue: FileManager.default.currentDirectoryPath)

        guard isValidSemver(version) else {
            throw ValidationError("Invalid app version. Expected semver, e.g. 0.1.0")
        }

        guard isValidSemver(minimumCoreVersion) else {
            throw ValidationError("Invalid minimum core version. Expected semver, e.g. 1.0.0")
        }

        let rootURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent(appID)
        let manifestURL = rootURL.appendingPathComponent("manifest.json")

        if FileManager.default.fileExists(atPath: manifestURL.path) {
            throw ValidationError("manifest.json already exists at \(manifestURL.path)")
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("patches"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("fixtures"), withIntermediateDirectories: true)

        let manifest = AppManifestTemplate(
            id: appID,
            title: title,
            description: description,
            publisher: publisher,
            version: version,
            minimumCoreVersion: minimumCoreVersion,
            doctypes: [],
            workflows: [],
            reports: [],
            automationRules: [],
            fixtures: [],
            schedulerEvents: [],
            extensionPoints: .init(documentEventSubscriptions: [], schedulerEvents: [])
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL)

        let patchesIndexURL = rootURL.appendingPathComponent("patches.json")
        let emptyPatches = try JSONEncoder().encode(PatchesIndex(patches: []))
        try emptyPatches.write(to: patchesIndexURL)

        let readmeURL = rootURL.appendingPathComponent("README.md")
        let readme = "# \(title)\n\n\(description)\n"
        try readme.write(to: readmeURL, atomically: true, encoding: .utf8)

        printSuccess("App scaffold created at \(rootURL.path)")
        print("Created:")
        print("- \(manifestURL.path)")
        print("- \(rootURL.appendingPathComponent("patches").path)/")
        print("- \(patchesIndexURL.path)")
        print("- \(rootURL.appendingPathComponent("fixtures").path)/")
        print("- \(readmeURL.path)")
    }

    private struct AppManifestTemplate: Codable {
        struct ExtensionPoints: Codable {
            let documentEventSubscriptions: [String]
            let schedulerEvents: [String]
        }

        let id: String
        let title: String
        let description: String
        let publisher: String
        let version: String
        let minimumCoreVersion: String
        let doctypes: [String]
        let workflows: [String]
        let reports: [String]
        let automationRules: [String]
        let fixtures: [String]
        let schedulerEvents: [String]
        let extensionPoints: ExtensionPoints
    }

    private struct PatchesIndex: Codable {
        let patches: [String]
    }
}
