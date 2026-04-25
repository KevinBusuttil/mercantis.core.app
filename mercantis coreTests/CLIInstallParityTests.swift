//
//  CLIInstallParityTests.swift
//  mercantis coreTests
//
//  Covers P2.3: the CLI's `install-app` command and the app's `AppInstaller`
//  share one install pipeline. These tests pin the JSON-data convenience APIs
//  the CLI uses (`AppInstaller.install(manifestData:)`,
//  `AppInstaller.validate(manifestData:)`) so a regression in either path is
//  caught here.
//

import XCTest
import GRDB
@testable import mercantis_core

final class CLIInstallParityTests: XCTestCase {

    // MARK: - Fixtures

    private func sampleDocType(appId: String) -> DocType {
        DocType(
            id: "Article",
            name: "Article",
            module: "Library",
            appId: appId,
            isChildTable: false,
            isSubmittable: false,
            fields: [
                TestSupport.textField("title", required: true),
                TestSupport.numberField("page_count")
            ],
            permissions: [TestSupport.permissionRule()],
            autoname: "naming_series:AR.#######",
            syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
            indexes: [IndexDefinition(fieldKey: "title", unique: false)],
            searchFields: ["title"],
            titleField: "title"
        )
    }

    private func sampleManifest(id: String = "app.mercantis.library") -> AppManifest {
        AppManifest(
            id: id,
            name: "Library",
            version: "0.1.0",
            minimumCoreVersion: "1.0.0",
            description: "Sample manifest",
            doctypes: [sampleDocType(appId: id)],
            workflows: [],
            permissions: [],
            reports: [],
            automationRules: [],
            dashboards: [],
            localizations: [],
            extensionPoints: .empty
        )
    }

    private func encode(_ manifest: AppManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }

    private func makeInstaller(harness: TestSupport.Harness) -> AppInstaller {
        AppInstaller(
            database: harness.database,
            schemaValidator: SchemaValidator(),
            registry: harness.registry
        )
    }

    // MARK: - Decode helpers

    func testDecodeManifestFromJSONRoundTripsAllFields() throws {
        let manifest = sampleManifest()
        let data = try encode(manifest)

        let decoded = try AppInstaller.decodeManifest(from: data)
        XCTAssertEqual(decoded.id, manifest.id)
        XCTAssertEqual(decoded.name, manifest.name)
        XCTAssertEqual(decoded.version, manifest.version)
        XCTAssertEqual(decoded.doctypes.map(\.id), manifest.doctypes.map(\.id))
    }

    func testDecodeManifestSurfacesDecodeFailureAsTypedError() {
        let bad = Data("{not json".utf8)
        XCTAssertThrowsError(try AppInstaller.decodeManifest(from: bad)) { error in
            guard case AppInstaller.AppInstallerError.manifestDecodeFailed = error else {
                XCTFail("expected manifestDecodeFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - Dry-run validation

    func testValidateManifestDataReturnsManifestWithoutWriting() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        let installer = makeInstaller(harness: harness)
        let data = try encode(sampleManifest())

        let manifest = try installer.validate(manifestData: data)
        XCTAssertEqual(manifest.id, "app.mercantis.library")

        // No DB writes happened.
        let appsRowCount: Int = try harness.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM apps") ?? 0
        }
        XCTAssertEqual(appsRowCount, 0)

        let docTypesRowCount: Int = try harness.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM doctypes") ?? 0
        }
        XCTAssertEqual(docTypesRowCount, 0)
    }

    func testValidateManifestDataRejectsInvalidDocType() throws {
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        let installer = makeInstaller(harness: harness)
        let badDoc = DocType(
            id: "",                                // empty id ⇒ SchemaValidator rejects
            name: "Bad",
            module: "Library",
            appId: "app.mercantis.bad",
            isChildTable: false,
            fields: [],
            permissions: [],
            syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
            indexes: [],
            searchFields: [],
            titleField: ""
        )
        let manifest = AppManifest(
            id: "app.mercantis.bad",
            name: "Bad",
            version: "0.1.0",
            minimumCoreVersion: "1.0.0",
            description: "",
            doctypes: [badDoc],
            workflows: [],
            permissions: [],
            reports: [],
            automationRules: [],
            dashboards: [],
            localizations: [],
            extensionPoints: .empty
        )
        let data = try encode(manifest)

        XCTAssertThrowsError(try installer.validate(manifestData: data)) { error in
            guard case SchemaValidator.ValidationError.emptyDocTypeId = error else {
                XCTFail("expected emptyDocTypeId, got \(error)")
                return
            }
        }
    }

    // MARK: - Install via JSON

    func testInstallFromManifestDataMatchesDirectInstallEndState() throws {
        // Two parallel databases. One installs from raw JSON via the CLI's
        // shared entry point; the other installs the same `AppManifest`
        // through the in-process `install(_:)` call. Both should produce
        // identical engine-visible state.
        let cliHarness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: cliHarness.url) }
        let appHarness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: appHarness.url) }

        let cliInstaller = makeInstaller(harness: cliHarness)
        let appInstaller = makeInstaller(harness: appHarness)

        let manifest = sampleManifest()
        let data = try encode(manifest)

        let installedFromData = try cliInstaller.install(manifestData: data)
        try appInstaller.install(manifest)

        XCTAssertEqual(installedFromData.id, manifest.id)

        // Both DBs have one app row with canonical column names.
        for harness in [cliHarness, appHarness] {
            let row = try harness.database.read { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT id, name, version, payload FROM apps WHERE id = ?",
                    arguments: [manifest.id]
                )
            }
            let unwrapped = try XCTUnwrap(row, "expected apps row in \(harness.url.path)")
            XCTAssertEqual(unwrapped["id"] as String?, manifest.id)
            XCTAssertEqual(unwrapped["name"] as String?, manifest.name)
            XCTAssertEqual(unwrapped["version"] as String?, manifest.version)
            XCTAssertNotNil(unwrapped["payload"] as String?)
        }

        // Both DBs registered the DocType + its fields.
        for harness in [cliHarness, appHarness] {
            let docTypeRow = try harness.database.read { db in
                try Row.fetchOne(db, sql: "SELECT id, appId FROM doctypes WHERE id = ?", arguments: ["Article"])
            }
            let unwrapped = try XCTUnwrap(docTypeRow)
            XCTAssertEqual(unwrapped["id"] as String?, "Article")
            XCTAssertEqual(unwrapped["appId"] as String?, manifest.id)

            let fieldRows = try harness.database.read { db in
                try Row.fetchAll(
                    db,
                    sql: "SELECT fieldKey FROM fields WHERE docTypeId = ? ORDER BY fieldKey",
                    arguments: ["Article"]
                )
            }
            XCTAssertEqual(
                fieldRows.compactMap { $0["fieldKey"] as String? },
                ["page_count", "title"]
            )

            // Both DBs enqueued an `installApp` mutation.
            let queueCount: Int = try harness.database.read { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM sync_queue WHERE type = ?",
                    arguments: [MutationType.installApp.rawValue]
                ) ?? 0
            }
            XCTAssertEqual(queueCount, 1)
        }
    }

    func testInstallFromManifestDataCreatesExpressionIndex() throws {
        // The DocType declares an IndexDefinition on `title`. P2.5 wires
        // declared indexes to real SQLite expression indexes via
        // `MetadataRegistry.register`; the CLI must inherit that for free
        // (P2.3 known-follow-up from the proposal).
        let harness = try TestSupport.makeHarness()
        defer { TestSupport.cleanUp(databaseURL: harness.url) }

        let installer = makeInstaller(harness: harness)
        let data = try encode(sampleManifest())

        try installer.install(manifestData: data)

        let indexNames = try harness.database.read { db in
            try Row
                .fetchAll(
                    db,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'documents'"
                )
                .compactMap { $0["name"] as String? }
        }
        XCTAssertTrue(
            indexNames.contains(where: { $0.hasPrefix("idx_doc_Article_title") }),
            "expected expression index for Article.title; got \(indexNames)"
        )
    }

    // MARK: - Lenient FieldDefinition decode (P2.3 ancillary)

    func testFieldDefinitionDecodesWithoutLayoutFields() throws {
        // Manifests authored by hand or by the CLI scaffold may omit the
        // `section` / `column` / `collapsible` keys. The decoder treats them
        // as optional and falls back to the `init` defaults so the install
        // pipeline doesn't reject a perfectly valid lean field.
        let json = """
        {
            "key": "title",
            "label": "Title",
            "type": "text",
            "required": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FieldDefinition.self, from: json)
        XCTAssertEqual(decoded.key, "title")
        XCTAssertEqual(decoded.required, true)
        XCTAssertNil(decoded.section)
        XCTAssertNil(decoded.column)
        XCTAssertEqual(decoded.collapsible, false)
        XCTAssertEqual(decoded.isSynced, true)            // default
        XCTAssertEqual(decoded.isSearchable, false)
        XCTAssertEqual(decoded.allowOnSubmit, false)
        XCTAssertTrue(decoded.validationRules.isEmpty)
    }

    func testFieldDefinitionDecodesWithLegacyAndNewKeysMixed() throws {
        // A manifest that does include the layout keys still round-trips.
        let original = FieldDefinition(
            key: "amount",
            label: "Amount",
            type: .currency,
            required: false,
            section: "Totals",
            column: 2,
            collapsible: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FieldDefinition.self, from: data)
        XCTAssertEqual(decoded.section, "Totals")
        XCTAssertEqual(decoded.column, 2)
        XCTAssertEqual(decoded.collapsible, true)
    }
}
