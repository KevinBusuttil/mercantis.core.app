import ArgumentParser
import Foundation
import MercantisCore

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

        let name = prompt("App Name")
        let description = prompt("App Description")
        let version = prompt("App Version", defaultValue: "0.1.0")
        let minimumCoreVersion = prompt("Minimum Core Version", defaultValue: "1.0.0")
        let outputDirectory = prompt("Output directory", defaultValue: FileManager.default.currentDirectoryPath)
        let outputDirectoryURL = URL(fileURLWithPath: outputDirectory)

        guard isValidSemver(version) else {
            throw ValidationError("Invalid App Version. Expected semver, e.g. 0.1.0")
        }

        guard isValidSemver(minimumCoreVersion) else {
            throw ValidationError("Invalid minimum core version. Expected semver, e.g. 1.0.0")
        }

        var isDirectory: ObjCBool = false
        let outputPathExists = FileManager.default.fileExists(atPath: outputDirectoryURL.path, isDirectory: &isDirectory)
        if outputPathExists && !isDirectory.boolValue {
            throw ValidationError("Output directory path exists but is not a directory: \(outputDirectoryURL.path)")
        }

        let rootURL = outputDirectoryURL.appendingPathComponent(appID)
        let manifestURL = rootURL.appendingPathComponent("manifest.json")

        if FileManager.default.fileExists(atPath: manifestURL.path) {
            throw ValidationError("manifest.json already exists at \(manifestURL.path)")
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("patches"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("fixtures"), withIntermediateDirectories: true)

        // Scaffold the canonical AppManifest shape so `mercantis install-app`
        // can decode it directly via MercantisCore (P2.3).
        let manifest = AppManifest(
            id: appID,
            name: name,
            version: version,
            minimumCoreVersion: minimumCoreVersion,
            description: description,
            doctypes: [],
            workflows: [],
            permissions: [],
            reports: [],
            automationRules: [],
            dashboards: [],
            localizations: [],
            extensionPoints: .empty
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL)

        let patchesIndexURL = rootURL.appendingPathComponent("patches").appendingPathComponent("patches.json")
        let emptyPatches = try JSONEncoder().encode(PatchesIndex(patches: []))
        try emptyPatches.write(to: patchesIndexURL)

        let readmeURL = rootURL.appendingPathComponent("README.md")
        let readme = "# \(name)\n\n\(description)\n"
        try readme.write(to: readmeURL, atomically: true, encoding: .utf8)

        printSuccess("App scaffold created at \(rootURL.path)")
        print("Created:")
        print("- \(manifestURL.path)")
        print("- \(rootURL.appendingPathComponent("patches").path)/")
        print("- \(patchesIndexURL.path)")
        print("- \(rootURL.appendingPathComponent("fixtures").path)/")
        print("- \(readmeURL.path)")
    }

    private struct PatchesIndex: Codable {
        let patches: [String]
    }
}
