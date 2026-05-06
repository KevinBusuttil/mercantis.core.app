//
//  FileSystemCloudAdapter.swift
//  mercantis core
//
//  Phase D / §3.5 (ADR-047) — Reference `CloudAdapter` implementation that
//  uses a shared filesystem directory as the "cloud". Useful for:
//  - iCloud Drive / Dropbox / OneDrive / SMB shares as the transport,
//  - LAN sync via a shared volume,
//  - test scenarios where two adapters point at the same temp directory
//    to simulate two devices.
//
//  This is genuinely peer-to-peer: there is no central server. Each device
//  writes its own mutations into its own subdirectory, and pulls peer
//  subdirectories on each `pullMutations(...)` call. Cross-peer ordering
//  is by per-peer monotonic sequence inside the adapter.
//

import Foundation

/// Filesystem-backed `CloudAdapter`. (ADR-047)
public final class FileSystemCloudAdapter: CloudAdapter, @unchecked Sendable {

    private let rootURL: URL
    private let localDeviceId: String
    private let fileManager: FileManager
    private let lock = NSLock()

    /// Local push counter — monotonic per device. The N-th mutation pushed
    /// from this device lands at `<root>/<localDeviceId>/<N>.json`.
    private var localPushSequence: Int64
    /// Per-peer cursor: max sequence we have already ingested from each
    /// peer device. Persists across process restarts.
    private var peerCursors: [String: Int64]
    /// Synthetic global counter we hand back as `RemoteMutation.serverSequence`.
    /// Monotonic so `SyncEngine.lastServerSequence` keeps working unchanged.
    private var globalReceiveSequence: Int64

    public init(
        rootURL: URL,
        localDeviceId: String,
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL
        self.localDeviceId = localDeviceId
        self.fileManager = fileManager

        try Self.ensureDirectory(rootURL, fileManager: fileManager)
        let myDir = rootURL.appendingPathComponent(localDeviceId, isDirectory: true)
        try Self.ensureDirectory(myDir, fileManager: fileManager)

        // Load adapter state from `<myDir>/.adapter-state.json` if present.
        let stateURL = myDir.appendingPathComponent(Self.stateFileName)
        if fileManager.fileExists(atPath: stateURL.path),
           let data = try? Data(contentsOf: stateURL),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            self.localPushSequence = decoded.localPushSequence
            self.peerCursors = decoded.peerCursors
            self.globalReceiveSequence = decoded.globalReceiveSequence
        } else {
            self.localPushSequence = 0
            self.peerCursors = [:]
            self.globalReceiveSequence = 0
        }
    }

    // MARK: - CloudAdapter

    public func pushMutations(_ mutations: [MutationRecord]) async throws -> [SyncAcknowledgement] {
        lock.lock(); defer { lock.unlock() }

        var acks: [SyncAcknowledgement] = []
        let myDir = rootURL.appendingPathComponent(localDeviceId, isDirectory: true)
        try Self.ensureDirectory(myDir, fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        for mutation in mutations {
            localPushSequence += 1
            let url = myDir.appendingPathComponent("\(localPushSequence).json")
            let envelope = MutationEnvelope(
                sourceDeviceId: localDeviceId,
                peerSequence: localPushSequence,
                record: mutation
            )
            let data = try encoder.encode(envelope)
            try data.write(to: url, options: .atomic)
            acks.append(SyncAcknowledgement(
                mutationId: mutation.id,
                serverSequence: localPushSequence
            ))
        }

        try persistStateUnlocked()
        return acks
    }

    public func pullMutations(since version: SyncVersion) async throws -> [RemoteMutation] {
        lock.lock(); defer { lock.unlock() }

        let cutoff = version.serverSequence
        var collected: [RemoteMutation] = []

        guard let peers = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Walk peer subdirectories in deterministic order so the global
        // sequence we mint is reproducible across runs against the same
        // shared root.
        for peerDir in peers.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let peer = peerDir.lastPathComponent
            guard peer != localDeviceId else { continue }
            // Each peer's dir is one device id; non-directory entries are skipped.
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: peerDir.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let peerCursor = peerCursors[peer] ?? 0
            guard let mutationFiles = try? fileManager.contentsOfDirectory(
                at: peerDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            // Each mutation file is named `<peerSequence>.json`. Filter by
            // cursor and sort by sequence.
            var pending: [(Int64, URL)] = []
            for url in mutationFiles where url.pathExtension == "json" {
                let stem = url.deletingPathExtension().lastPathComponent
                if let seq = Int64(stem), seq > peerCursor {
                    pending.append((seq, url))
                }
            }
            pending.sort { $0.0 < $1.0 }

            for (peerSeq, url) in pending {
                guard let bytes = try? Data(contentsOf: url) else { continue }
                guard let envelope = try? decoder.decode(MutationEnvelope.self, from: bytes) else {
                    continue
                }
                globalReceiveSequence += 1
                if globalReceiveSequence > cutoff {
                    collected.append(RemoteMutation(
                        record: envelope.record,
                        serverSequence: globalReceiveSequence
                    ))
                }
                peerCursors[peer] = peerSeq
            }
        }

        try persistStateUnlocked()
        return collected
    }

    // MARK: - Inspection

    public func currentLocalPushSequence() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return localPushSequence
    }

    public func currentPeerCursor(for peerDeviceId: String) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return peerCursors[peerDeviceId] ?? 0
    }

    public func currentGlobalReceiveSequence() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return globalReceiveSequence
    }

    // MARK: - Persistence

    private static let stateFileName = ".adapter-state.json"

    private struct State: Codable {
        let localPushSequence: Int64
        let peerCursors: [String: Int64]
        let globalReceiveSequence: Int64
    }

    private struct MutationEnvelope: Codable {
        let sourceDeviceId: String
        let peerSequence: Int64
        let record: MutationRecord
    }

    /// Caller must hold `lock`.
    private func persistStateUnlocked() throws {
        let state = State(
            localPushSequence: localPushSequence,
            peerCursors: peerCursors,
            globalReceiveSequence: globalReceiveSequence
        )
        let myDir = rootURL.appendingPathComponent(localDeviceId, isDirectory: true)
        try Self.ensureDirectory(myDir, fileManager: fileManager)
        let url = myDir.appendingPathComponent(Self.stateFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    private static func ensureDirectory(_ url: URL, fileManager: FileManager) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
