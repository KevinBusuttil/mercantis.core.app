import ArgumentParser
import Foundation

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
        let naming = try promptNamingConfig()
        let fields = try promptFields()
        let titleField = promptTitleField(from: fields)
        let permissions = try promptPermissions(isSubmittable: isSubmittable)

        if let app {
            try appendDocTypeToManifest(at: app, id: id, name: name, module: module, isSubmittable: isSubmittable, isSingle: isSingle, isChildTable: isChildTable, naming: naming, fields: fields, titleField: titleField, permissions: permissions)
        } else {
            try writeStandaloneDocType(id: id, name: name, module: module, isSubmittable: isSubmittable, isSingle: isSingle, isChildTable: isChildTable, naming: naming, fields: fields, titleField: titleField, permissions: permissions)
        }
    }

    private func writeStandaloneDocType(
        id: String,
        name: String,
        module: String,
        isSubmittable: Bool,
        isSingle: Bool,
        isChildTable: Bool,
        naming: NamingConfig,
        fields: [FieldDefinitionTemplate],
        titleField: String,
        permissions: [PermissionRuleTemplate]
    ) throws {
        let payload = makeDocTypePayload(
            id: id,
            name: name,
            module: module,
            appId: "",
            isSubmittable: isSubmittable,
            isSingle: isSingle,
            isChildTable: isChildTable,
            naming: naming,
            fields: fields,
            titleField: titleField,
            permissions: permissions
        )

        let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("\(id).doctype.json")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            throw ValidationError("File already exists at \(outputURL.path)")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(payload).write(to: outputURL)

        printSuccess("DocType scaffold created.")
        print("Created:")
        print("- \(outputURL.path)")
    }

    private func appendDocTypeToManifest(
        at appDirectory: String,
        id: String,
        name: String,
        module: String,
        isSubmittable: Bool,
        isSingle: Bool,
        isChildTable: Bool,
        naming: NamingConfig,
        fields: [FieldDefinitionTemplate],
        titleField: String,
        permissions: [PermissionRuleTemplate]
    ) throws {
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

        let appId = (manifestObject["id"] as? String) ?? ""
        let payload = makeDocTypePayload(
            id: id,
            name: name,
            module: module,
            appId: appId,
            isSubmittable: isSubmittable,
            isSingle: isSingle,
            isChildTable: isChildTable,
            naming: naming,
            fields: fields,
            titleField: titleField,
            permissions: permissions
        )

        var doctypes = manifestObject["doctypes"] as? [Any] ?? []
        doctypes.append(try jsonObject(payload))
        manifestObject["doctypes"] = doctypes

        let updatedData = try JSONSerialization.data(withJSONObject: manifestObject, options: [.prettyPrinted])
        try updatedData.write(to: manifestURL)

        printSuccess("DocType scaffold created.")
        print("Updated:")
        print("- \(manifestURL.path)")
    }

    private func makeDocTypePayload(
        id: String,
        name: String,
        module: String,
        appId: String,
        isSubmittable: Bool,
        isSingle: Bool,
        isChildTable: Bool,
        naming: NamingConfig,
        fields: [FieldDefinitionTemplate],
        titleField: String,
        permissions: [PermissionRuleTemplate]
    ) -> DocTypeTemplate {
        DocTypeTemplate(
            id: id,
            name: name,
            module: module,
            appId: appId,
            isChildTable: isChildTable,
            isSubmittable: isSubmittable,
            isSingle: isSingle,
            fields: fields,
            permissions: permissions,
            // Phase 1 CLI scaffolds to ADR-014's default naming conflict strategy (LWW).
            syncPolicy: .init(conflictResolution: "lastWriteWins", immutableAfterSubmit: false),
            indexes: [],
            workflowId: nil,
            autoname: naming.autoname,
            namingSeries: naming.namingSeries,
            namingField: naming.namingField,
            namingFormat: naming.namingFormat,
            searchFields: [],
            titleField: titleField
        )
    }

    private func promptNamingConfig() throws -> NamingConfig {
        while true {
            let input = prompt("Naming strategy (\(NamingStrategyOption.promptValues))", defaultValue: NamingStrategyOption.uuid.rawValue)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            switch input {
            case NamingStrategyOption.uuid.rawValue:
                return NamingConfig(autoname: "UUID")
            case NamingStrategyOption.series.rawValue:
                let pattern = promptRequired("Series pattern (e.g. AR.#######)")
                return NamingConfig(autoname: "naming_series:\(pattern)", namingSeries: pattern)
            case NamingStrategyOption.field.rawValue:
                let fieldKey = promptRequired("Field key for naming (e.g. email)")
                return NamingConfig(autoname: "field:\(fieldKey)", namingField: fieldKey)
            case NamingStrategyOption.prompt.rawValue:
                return NamingConfig(autoname: "prompt")
            case NamingStrategyOption.format.rawValue:
                let format = promptRequired("Format string (e.g. {company_abbr}-{naming_series})")
                return NamingConfig(autoname: "format:\(format)", namingFormat: format)
            default:
                printError("Invalid naming strategy. Choose: \(NamingStrategyOption.promptValues).")
            }
        }
    }

    private func promptFields() throws -> [FieldDefinitionTemplate] {
        var fields: [FieldDefinitionTemplate] = []
        var addAnother = true

        while addAnother {
            let key = promptRequired("Field key (e.g. article_name)")
            let label = prompt("Field label", defaultValue: humanizedLabel(from: key))
            let fieldType = try promptFieldType()

            var options: [String]?
            var linkedDocType: String?
            var childDocType: String?

            switch fieldType {
            case .select:
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
                FieldDefinitionTemplate(
                    key: key,
                    label: label,
                    type: fieldType.fieldTypeValue,
                    required: required,
                    defaultValue: nil,
                    options: options,
                    linkedDocType: linkedDocType,
                    childDocType: childDocType,
                    validationRules: [],
                    visibilityExpression: nil,
                    readOnlyExpression: nil,
                    formulaExpression: nil,
                    permissions: nil,
                    isSearchable: false,
                    isSynced: true,
                    allowOnSubmit: false
                )
            )

            addAnother = promptYesNo("Add another field?", defaultValue: false)
        }

        return fields
    }

    private func promptPermissions(isSubmittable: Bool) throws -> [PermissionRuleTemplate] {
        var permissions: [PermissionRuleTemplate] = []
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
                PermissionRuleTemplate(
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

    private func promptTitleField(from fields: [FieldDefinitionTemplate]) -> String {
        while true {
            let value = prompt("Title field key (optional)", defaultValue: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || fields.contains(where: { $0.key == value }) {
                return value
            }
            printError("Title field must match one of the entered field keys.")
        }
    }

    private func promptFieldType() throws -> SupportedFieldType {
        while true {
            let input = prompt("Field type (\(SupportedFieldType.promptValues))", defaultValue: SupportedFieldType.text.rawValue)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let value = SupportedFieldType(rawValue: input) {
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
        input
            .split(separator: ",")
            .map { String($0) }
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
            case "y", "yes":
                return true
            case "n", "no":
                return false
            default:
                printError("Please enter y or n.")
            }
        }
    }

    private func humanizedLabel(from key: String) -> String {
        key
            .split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
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

    private enum SupportedFieldType: String, CaseIterable {
        case text
        case number
        case date
        case datetime
        case check
        case select
        case link
        case table
        case currency
        case float
        case attach
        case image
        case textEditor

        static var promptValues: String {
            allCases.map(\.rawValue).joined(separator: "/")
        }

        var fieldTypeValue: String {
            switch self {
            case .text: return "text"
            case .number: return "number"
            case .date: return "date"
            case .datetime: return "datetime"
            case .check: return "boolean"
            case .select: return "select"
            case .link: return "link"
            case .table: return "table"
            case .currency: return "currency"
            case .float: return "decimal"
            case .attach: return "attachment"
            case .image: return "attachment"
            case .textEditor: return "longText"
            }
        }
    }

    private struct NamingConfig {
        let autoname: String
        let namingSeries: String?
        let namingField: String?
        let namingFormat: String?

        init(autoname: String, namingSeries: String? = nil, namingField: String? = nil, namingFormat: String? = nil) {
            self.autoname = autoname
            self.namingSeries = namingSeries
            self.namingField = namingField
            self.namingFormat = namingFormat
        }
    }

    private struct DocTypeTemplate: Codable {
        let id: String
        let name: String
        let module: String
        let appId: String
        let isChildTable: Bool
        let isSubmittable: Bool
        let isSingle: Bool
        let fields: [FieldDefinitionTemplate]
        let permissions: [PermissionRuleTemplate]
        let syncPolicy: SyncPolicyTemplate
        let indexes: [IndexDefinitionTemplate]
        let workflowId: String?
        let autoname: String
        let namingSeries: String?
        let namingField: String?
        let namingFormat: String?
        let searchFields: [String]
        let titleField: String
    }

    private struct FieldDefinitionTemplate: Codable {
        let key: String
        let label: String
        let type: String
        let required: Bool
        let defaultValue: String?
        let options: [String]?
        let linkedDocType: String?
        let childDocType: String?
        let validationRules: [ValidationRuleTemplate]
        let visibilityExpression: String?
        let readOnlyExpression: String?
        let formulaExpression: String?
        let permissions: FieldPermissionTemplate?
        let isSearchable: Bool
        let isSynced: Bool
        let allowOnSubmit: Bool
    }

    private struct ValidationRuleTemplate: Codable {
        let ruleType: String
        let expression: String
        let message: String
    }

    private struct FieldPermissionTemplate: Codable {
        let readRoles: [String]
        let writeRoles: [String]
    }

    private struct PermissionRuleTemplate: Codable {
        let role: String
        let canRead: Bool
        let canWrite: Bool
        let canCreate: Bool
        let canDelete: Bool
        let canSubmit: Bool
        let canAmend: Bool
    }

    private struct SyncPolicyTemplate: Codable {
        let conflictResolution: String
        let immutableAfterSubmit: Bool
    }

    private struct IndexDefinitionTemplate: Codable {
        let fieldKey: String
        let unique: Bool
    }
}
