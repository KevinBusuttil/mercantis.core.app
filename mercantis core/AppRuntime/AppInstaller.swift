//
//  AppInstaller.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Installs, updates, and uninstalls app manifests. (ADR-004)
/// App state changes are distributed via the sync engine so all devices
/// in a workspace share the same app state.
public final class AppInstaller {

    private let database: MercantisDatabase
    private let schemaValidator: SchemaValidator

    public init(database: MercantisDatabase, schemaValidator: SchemaValidator) {
        self.database = database
        self.schemaValidator = schemaValidator
    }

    /// Install an app from its manifest. Validates all DocTypes before committing.
    public func install(_ manifest: AppManifest) throws {
        // Validate every DocType in the manifest
        for docType in manifest.doctypes {
            try schemaValidator.validate(docType)
        }
        // TODO: Write DocTypes, workflows, permissions, reports, automation rules to metadata tables
        // TODO: Append installApp mutation to sync_queue
    }

    /// Uninstall an app, removing its DocTypes and associated metadata.
    public func uninstall(appId: String) throws {
        // TODO: Remove app's DocTypes, workflows, etc. from metadata tables
        // TODO: Append mutation to sync_queue
    }
}
