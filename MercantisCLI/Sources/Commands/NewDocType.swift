import ArgumentParser
import Foundation
import MercantisCore

struct NewDocType: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new-doctype",
        abstract: "Interactively scaffold a new DocType definition."
    )

    @Option(name: .long, help: "App manifest directory containing manifest.json. If omitted, writes a standalone .doctype.json file in the current directory.")
    var app: String?

    mutating func run() throws {
        let id = promptRequired("DocType ID (e.g. Article)")
        let name = prompt("Display Name", defaultValue: id)
        let module = promptRequired("Module (e.g. Library Management)")
        let isSubmittable = promptYesNo("Is Submittable?", defaultValue: false)
        let isSingle = promptYesNo("Is Single?", defaultValue: false)
        let isChildTable = promptYesNo("Is Child Table?", defaultValue: false)
        let autoname = promptAutoname()
        let fields = try promptFields()
        let titleField = promptTitleField(from: fields)
        let permissions = promptPermissions(isSubmittable: isSubmittable)

        let docType = DocType(
            id: id,
            name: name,
            module: module,
            appId: "",
            isChildTable: isChildTable,
            isSubmittable: isSubmittable,
            isSingle: isSingle,
            fields: fields,
            permissions: permissions,
            autoname: autoname,
            // Phase 1 scaffolds the default sync policy used for generic
            // business DocTypes; submittable types pick up version-checked +
            // immutable-after-submit.
            syncPolicy: SyncPolicy(
                conflictResolution: isSubmittable ? .versionChecked : .lastWriteWins,
                immutableAfterSubmit: isSubmittable
            ),
            indexes: [],
            searchFields: [],
            titleField: titleField
        )

        // Use Core's SchemaValidator with `validatesExpressions = false` —
        // the scaffold doesn't yet have any expressions, but if the user
        // adds them by hand the install path catches undeclared field
        // references at install time (P2.1).
        var validator = SchemaValidator()
        validator.validatesExpressions = false
        try validator.validate(docType)

        if let app {
            try appendDocTypeToManifest(at: app, docType: docType)
        } else {
            try writeStandaloneDocType(docType: docType)
        }
    }

    private func writeStandaloneDocType(docType: DocType) throws {
        let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("\(docType.id).doctype.json")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            throw ValidationError("File already exists at \(outputURL.path)")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(docType).write(to: outputURL)

        printSuccess("DocType scaffold created.")
        print("Created:")
        print("- \(outputURL.path)")
    }

    private func appendDocTypeToManifest(at appDirectory: String, docType: DocType) throws {
        let appURL = URL(fileURLWithPath: appDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ValidationError("App path is not a directory: \(appURL.path)")
        }

        let manifestURL = appURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ValidationError("manifest.json not found in \(appURL.path)")
        }

        let manifestData = try Data(contentsOf: manifestURL)
        guard var manifestObject = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            throw ValidationError("manifest.json must be a JSON object")
        }

        // Stamp the owning app id on the new DocType so registry lookups by
        // app id (uninstall, restore) match the manifest contents.
        var stamped = docType
        stamped.appId = (manifestObject["id"] as? String) ?? ""

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let docTypeData = try encoder.encode(stamped)
        let docTypeJSON = try JSONSerialization.jsonObject(with: docTypeData)

        var doctypes = manifestObject["doctypes"] as? [Any] ?? []
        doctypes.append(docTypeJSON)
        manifestObject["doctypes"] = doctypes

        let updatedData = try JSONSerialization.data(
            withJSONObject: manifestObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updatedData.write(to: manifestURL)

        printSuccess("DocType scaffold created.")
        print("Updated:")
        print("- \(manifestURL.path)")
    }

    // MARK: - Prompts

    private func promptAutoname() -> String? {
        while true {
            let input = prompt(
                "Naming strategy (\(NamingStrategyOption.promptValues))",
                defaultValue: NamingStrategyOption.uuid.rawValue
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

            switch input {
            case NamingStrategyOption.uuid.rawValue:
                return "UUID"
            case NamingStrategyOption.series.rawValue:
                let pattern = promptRequired("Series pattern (e.g. AR.#######)")
                return "naming_series:\(pattern)"
            case NamingStrategyOption.field.rawValue:
                let fieldKey = promptRequired("Field key for naming (e.g. email)")
                return "field:\(fieldKey)"
            case NamingStrategyOption.prompt.rawValue:
                return "prompt"
            case NamingStrategyOption.format.rawValue:
                let format = promptRequired("Format string (e.g. {company_abbr}-{naming_series})")
                return "format:\(format)"
            default:
                printError("Invalid naming strategy. Choose: \(NamingStrategyOption.promptValues).")
            }
        }
    }

    private func promptFields() throws -> [FieldDefinition] {
        var fields: [FieldDefinition] = []
        var addAnother = true

        while addAnother {
            let key = promptRequired("Field key (e.g. article_name)")
            let label = prompt("Field label", defaultValue: humanizedLabel(from: key))
            let type = try promptFieldType()

            var options: [String]?
            var linkedDocType: String?
            var childDocType: String?

            switch type {
            case .select, .multiselect:
                options = promptSelectOptions()
            case .link:
                linkedDocType = promptRequired("Linked DocType name")
            case .table:
                childDocType = promptRequired("Child table DocType name")
            default:
                break
            }

            let required = promptYesNo("Required?", defaultValue: false)
            fields.append(
                FieldDefinition(
                    key: key,
                    label: label,
                    type: type,
                    required: required,
                    options: options,
                    linkedDocType: linkedDocType,
                    childDocType: childDocType
                )
            )

            addAnother = promptYesNo("Add another field?", defaultValue: false)
        }

        return fields
    }

    private func promptPermissions(isSubmittable: Bool) -> [PermissionRule] {
        var permissions: [PermissionRule] = []
        var addAnother = true

        while addAnother {
            let role = promptRequired("Role name (e.g. Librarian)")
            let canRead = promptYesNo("Read?", defaultValue: true)
            let canWrite = promptYesNo("Write?", defaultValue: false)
            let canCreate = promptYesNo("Create?", defaultValue: false)
            let canDelete = promptYesNo("Delete?", defaultValue: false)
            let canSubmit = isSubmittable ? promptYesNo("Submit?", defaultValue: false) : false
            let canAmend = isSubmittable ? promptYesNo("Amend?", defaultValue: false) : false

            permissions.append(
                PermissionRule(
                    role: role,
                    canRead: canRead,
                    canWrite: canWrite,
                    canCreate: canCreate,
                    canDelete: canDelete,
                    canSubmit: canSubmit,
                    canAmend: canAmend
                )
            )

            addAnother = promptYesNo("Add another permission?", defaultValue: false)
        }

        return permissions
    }

    private func promptTitleField(from fields: [FieldDefinition]) -> String {
        while true {
            let value = prompt("Title field key (optional; leave blank for none)", defaultValue: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || fields.contains(where: { $0.key == value }) {
                return value
            }
            printError("Title field must match one of the entered field keys.")
        }
    }

    private func promptFieldType() throws -> FieldType {
        let allowed = FieldType.allCases.map(\.rawValue).joined(separator: "/")
        while true {
            let input = prompt("Field type (\(allowed))", defaultValue: FieldType.text.rawValue)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = FieldType(rawValue: input) {
                return value
            }
            printError("Invalid field type.")
        }
    }

    private func promptSelectOptions() -> [String] {
        while true {
            let firstLine = prompt("Select options (comma-separated or first option)")
            var values = splitOptions(firstLine)

            if !firstLine.contains(",") {
                while true {
                    let next = prompt("Add option (leave empty to stop)")
                    if next.isEmpty { break }
                    values.append(contentsOf: splitOptions(next))
                }
            }

            let cleaned = values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !cleaned.isEmpty {
                return cleaned
            }

            printError("At least one option is required for select fields.")
        }
    }

    private func splitOptions(_ input: String) -> [String] {
        input.split(separator: ",").map { String($0) }
    }

    private func promptRequired(_ text: String) -> String {
        while true {
            let value = prompt(text).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
            printError("Value is required.")
        }
    }

    private func promptYesNo(_ text: String, defaultValue: Bool) -> Bool {
        while true {
            let defaultText = defaultValue ? "y" : "n"
            let value = prompt("\(text) (y/n)", defaultValue: defaultText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            switch value {
            case "y", "yes": return true
            case "n", "no": return false
            default: printError("Please enter y or n.")
            }
        }
    }

    private func humanizedLabel(from key: String) -> String {
        key
            .split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private enum NamingStrategyOption: String, CaseIterable {
        case uuid
        case series
        case field
        case prompt
        case format

        static var promptValues: String {
            allCases.map(\.rawValue).joined(separator: "/")
        }
    }
}
