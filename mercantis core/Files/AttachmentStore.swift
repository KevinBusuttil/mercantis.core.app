//
//  AttachmentStore.swift
//  mercantis core
//
//  Phase C / P3.1 (ADR-043) — Filesystem backend for attachment bytes.
//

import Foundation
import CryptoKit

/// Filesystem-backed byte store for attachments. Files are written under
/// `<rootURL>/<documentId>/<attachmentId>` so a per-document `deleteAll`
/// is one directory tree removal.
///
/// The store is intentionally dumb: it knows nothing about DocTypes,
/// permissions, or audit. Those concerns live one layer up in
/// `AttachmentManager`.
public final class AttachmentStore: @unchecked Sendable {

    public let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL
        self.fileManager = fileManager
        try Self.ensureDirectory(rootURL, fileManager: fileManager)
    }

    /// Convenience: derive an attachment root next to a `MercantisDatabase`
    /// file. Result: `<dbDir>/attachments/`.
    public convenience init(beside database: MercantisDatabase) throws {
        let dbDir = database.databaseURL.deletingLastPathComponent()
        try self.init(rootURL: dbDir.appendingPathComponent("attachments", isDirectory: true))
    }

    // MARK: - Write

    /// Write `data` for `attachmentId` under `documentId`. Returns the
    /// relative storage path (always `"<documentId>/<attachmentId>"`),
    /// which is what `AttachmentManager` records in the metadata row.
    @discardableResult
    public func write(documentId: String, attachmentId: String, data: Data) throws -> String {
        let dir = rootURL.appendingPathComponent(documentId, isDirectory: true)
        try Self.ensureDirectory(dir, fileManager: fileManager)
        let target = dir.appendingPathComponent(attachmentId)
        try data.write(to: target, options: .atomic)
        return "\(documentId)/\(attachmentId)"
    }

    // MARK: - Read

    public func read(storagePath: String) throws -> Data {
        let url = rootURL.appendingPathComponent(storagePath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw AttachmentError.notFound(id: storagePath)
        }
        return try Data(contentsOf: url)
    }

    public func exists(storagePath: String) -> Bool {
        let url = rootURL.appendingPathComponent(storagePath)
        return fileManager.fileExists(atPath: url.path)
    }

    // MARK: - Delete

    /// Delete a single attachment file. Missing files are tolerated —
    /// the metadata row may already have been removed independently.
    public func delete(storagePath: String) throws {
        let url = rootURL.appendingPathComponent(storagePath)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Recursively delete every file under `<rootURL>/<documentId>/`.
    /// Used when a document is deleted (`AttachmentManager.deleteAll(for:)`).
    public func deleteAll(documentId: String) throws {
        let dir = rootURL.appendingPathComponent(documentId, isDirectory: true)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    // MARK: - Hashing

    /// Lower-case hex SHA-256 of `data`.
    public static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Internals

    private static func ensureDirectory(_ url: URL, fileManager: FileManager) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
