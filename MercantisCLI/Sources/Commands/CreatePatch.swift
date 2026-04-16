import ArgumentParser
import Foundation

struct CreatePatch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-patch",
        abstract: "Interactively create a new patch descriptor and append it to patches.json."
    )

    mutating func run() throws {
        let patchesDirectory = prompt("Patches directory", defaultValue: "./patches")
        let description = prompt("Patch description")

        guard !description.isEmpty else {
            throw ValidationError("Patch description is required")
        }

        let patchesURL = URL(fileURLWithPath: patchesDirectory)
        try FileManager.default.createDirectory(at: patchesURL, withIntermediateDirectories: true)

        let indexURL = patchesURL.appendingPathComponent("patches.json")
        var index = PatchIndex(patches: [])

        if FileManager.default.fileExists(atPath: indexURL.path) {
            let data = try Data(contentsOf: indexURL)
            index = try JSONDecoder().decode(PatchIndex.self, from: data)
        }

        let nextNumber = nextPatchNumber(from: index.patches)
        let slug = slugify(description)
        let patchName = String(format: "%03d_%@", nextNumber, slug.isEmpty ? "patch" : slug)

        let descriptor = PatchDescriptor(name: patchName, description: description, sql: [])
        let descriptorURL = patchesURL.appendingPathComponent("\(patchName).json")

        if FileManager.default.fileExists(atPath: descriptorURL.path) {
            throw ValidationError("Patch already exists: \(descriptorURL.path)")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(descriptor).write(to: descriptorURL)

        index.patches.append(patchName)
        try encoder.encode(index).write(to: indexURL)

        printSuccess("Created patch: \(descriptorURL.path)")
    }

    private func nextPatchNumber(from patchNames: [String]) -> Int {
        let maxNumber = patchNames
            .compactMap { Int($0.split(separator: "_").first ?? "") }
            .max() ?? 0
        return maxNumber + 1
    }

    private struct PatchIndex: Codable {
        var patches: [String]
    }

    private struct PatchDescriptor: Codable {
        let name: String
        let description: String
        let sql: [String]
    }
}
