//
//  TestSupport.swift
//  mercantis coreTests
//
//  Shared fixtures and builders for Mercantis Core tests.
//

import Foundation
import XCTest
@testable import mercantis_core

enum TestSupport {

    // MARK: - Database

    /// Return a fresh URL under the system temp directory for a one-off SQLite file.
    /// Each test should use its own URL and call `cleanUp(databaseURL:)` in tearDown.
    static func tempDatabaseURL(_ label: String = "mercantis-test") -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mercantis-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(label).sqlite")
    }

    /// Build a fully migrated `MercantisDatabase` at `url`.
    static func makeDatabase(at url: URL) throws -> MercantisDatabase {
        try MercantisDatabase(databaseURL: url)
    }

    /// Remove the temp directory that contains `url`. Safe to call in tearDown.
    static func cleanUp(databaseURL url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - DocType builders

    static func textField(
        _ key: String,
        label: String? = nil,
        required: Bool = false,
        allowOnSubmit: Bool = false
    ) -> FieldDefinition {
        FieldDefinition(
            key: key,
            label: label ?? key.capitalized,
            type: .text,
            required: required,
            allowOnSubmit: allowOnSubmit
        )
    }

    static func numberField(
        _ key: String,
        label: String? = nil,
        required: Bool = false
    ) -> FieldDefinition {
        FieldDefinition(
            key: key,
            label: label ?? key.capitalized,
            type: .number,
            required: required
        )
    }

    static func linkField(
        _ key: String,
        targeting docType: String
    ) -> FieldDefinition {
        FieldDefinition(
            key: key,
            label: key.capitalized,
            type: .link,
            required: false,
            linkedDocType: docType
        )
    }

    static func defaultSyncPolicy() -> SyncPolicy {
        SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false)
    }

    static func submittableSyncPolicy() -> SyncPolicy {
        SyncPolicy(conflictResolution: .versionChecked, immutableAfterSubmit: true)
    }

    static func permissionRule(role: String = "System Manager") -> PermissionRule {
        PermissionRule(
            role: role,
            canRead: true,
            canWrite: true,
            canCreate: true,
            canDelete: true,
            canSubmit: true,
            canAmend: true
        )
    }

    /// Build a minimal DocType with the given id and fields.
    static func makeDocType(
        id: String = "Note",
        module: String = "Core",
        appId: String = "app.mercantis.test",
        fields: [FieldDefinition] = [textField("title", required: true)],
        permissions: [PermissionRule] = [permissionRule()],
        isSubmittable: Bool = false,
        syncPolicy: SyncPolicy? = nil,
        indexes: [IndexDefinition] = [],
        titleField: String = "title"
    ) -> DocType {
        DocType(
            id: id,
            name: id,
            module: module,
            appId: appId,
            isChildTable: false,
            isSubmittable: isSubmittable,
            fields: fields,
            permissions: permissions,
            syncPolicy: syncPolicy ?? defaultSyncPolicy(),
            indexes: indexes,
            searchFields: [titleField],
            titleField: titleField
        )
    }

    // MARK: - Document builders

    static func makeDocument(
        id: String = UUID().uuidString,
        docType: String = "Note",
        fields: [String: FieldValue] = ["title": .string("Hello")],
        children: [String: [ChildRow]] = [:],
        docStatus: Int = 0,
        amendedFrom: String? = nil,
        syncVersion: Int64 = 0,
        updatedAt: Date = Date()
    ) -> Document {
        Document(
            id: id,
            docType: docType,
            company: "",
            status: "",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            syncVersion: syncVersion,
            syncState: .local,
            docStatus: docStatus,
            amendedFrom: amendedFrom,
            fields: fields,
            children: children
        )
    }

    // MARK: - DocumentEngine assembly

    struct Harness {
        let database: MercantisDatabase
        let registry: MetadataRegistry
        let emitter: EventEmitter
        let engine: DocumentEngine
        let url: URL
    }

    /// Spin up a DocumentEngine against a fresh on-disk SQLite file. Caller
    /// should clean up by calling `TestSupport.cleanUp(databaseURL: harness.url)`.
    static func makeHarness(
        deviceId: String = "test-device",
        userId: String = "test-user",
        pipeline: ValidationPipeline? = nil
    ) throws -> Harness {
        let url = tempDatabaseURL()
        let database = try makeDatabase(at: url)
        let registry = MetadataRegistry(database: database)
        let emitter = EventEmitter()
        let engine = DocumentEngine(
            database: database,
            registry: registry,
            deviceId: deviceId,
            userId: userId,
            eventEmitter: emitter,
            validationPipeline: pipeline ?? ValidationPipeline()
        )
        return Harness(database: database, registry: registry, emitter: emitter, engine: engine, url: url)
    }
}
