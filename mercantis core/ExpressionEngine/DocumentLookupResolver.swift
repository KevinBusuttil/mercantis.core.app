//
//  DocumentLookupResolver.swift
//  mercantis core
//
//  Cross-document `lookup(docType, name, field)` for the sandboxed
//  expression engine. (ADR-017, ADR-029, P2.2)
//
//  The evaluator is intentionally pure — it cannot reach the database on
//  its own. To answer `lookup("Item", item_code, "rate")` it asks a
//  `DocumentLookupResolver`. `DocumentEngine` conforms to the protocol
//  via an extension; tests can substitute an in-memory resolver.
//
//  `CachingDocumentLookupResolver` is the read-through cache the
//  proposal called for: a successful (or empty) lookup is memoized and
//  reused until a save / delete / submit / cancel event for the same
//  `(docType, id)` arrives via `EventEmitter`. Per-save invalidation
//  matches the pattern `MetaComposer` already uses for resolved-meta.
//

import Foundation

// MARK: - Resolver protocol

/// A way to fetch a single field value from a document by id. The
/// expression evaluator calls this when interpreting `lookup(...)`.
///
/// Returns `nil` if the document does not exist or the field is not
/// present. Throwing is reserved for genuine storage errors; the
/// evaluator turns thrown errors into `.null` so a transient I/O issue
/// does not crash a form's expression evaluation.
///
/// Conformance does not require `Sendable`. `DocumentEngine` is the
/// reference implementation and is not currently `Sendable`, but the
/// evaluator that owns the resolver is `@unchecked Sendable` and treats
/// it as opaque storage.
public protocol DocumentLookupResolver: AnyObject {
    func lookup(docType: String, name: String, field: String) throws -> FieldValue?
}

// MARK: - Caching wrapper

/// Read-through cache in front of a base `DocumentLookupResolver`.
///
/// **Cache-by-read.** A successful resolver call is memoized in a
/// `[CacheKey: [String: FieldValue?]]` map. The inner `FieldValue?`
/// preserves the distinction between "looked up and the field is
/// absent" (cached as `nil`) and "never looked up" (no entry).
///
/// **Per-save invalidation.** When constructed with an `EventEmitter`,
/// the resolver subscribes to `DocumentSavedEvent`, `DocumentDeletedEvent`,
/// `DocumentSubmittedEvent`, and `DocumentCancelledEvent`. On any event
/// for `(docType, id)`, every cached field for that key is dropped.
/// `DocumentAmendedEvent` is intentionally ignored — amends create a new
/// document id, which has no cache entries to invalidate, and the
/// original is unchanged.
///
/// The cache is process-local. Cross-device invalidation is implicit:
/// a remote write that arrives via `SyncEngine` lands through
/// `DocumentEngine.applyRemote(_:from:)`, which fires the same
/// `DocumentSavedEvent` (P0.2). Devices observe each other's writes
/// through their own engine's event stream.
public final class CachingDocumentLookupResolver: DocumentLookupResolver {

    public struct CacheKey: Hashable, Sendable {
        public let docType: String
        public let name: String

        public init(docType: String, name: String) {
            self.docType = docType
            self.name = name
        }
    }

    /// `weak` so callers like `DocumentEngine` can own the cache as a
    /// stored property without forming a retain cycle (`DocumentEngine`
    /// → cache → engine via `base`). When the base resolver is gone,
    /// lookups fail closed and return `nil` — same shape as a
    /// document-not-found result.
    private weak var base: DocumentLookupResolver?
    private var cache: [CacheKey: [String: FieldValue?]] = [:]
    private let lock = NSLock()
    private var subscriptionTokens: [SubscriptionToken] = []

    /// Wrap `base` with a read-through cache.
    ///
    /// - Parameters:
    ///   - base: The underlying resolver — typically a `DocumentEngine`.
    ///     Held weakly; callers must keep the base alive for the
    ///     lifetime of the cache.
    ///   - eventEmitter: The emitter to subscribe to for per-save
    ///     invalidation. Pass the same emitter the engine publishes on
    ///     so cache entries are dropped on every relevant write.
    ///     Pass `nil` for tests that drive invalidation manually.
    public init(base: DocumentLookupResolver, eventEmitter: EventEmitter? = nil) {
        self.base = base
        if let emitter = eventEmitter {
            subscribe(to: emitter)
        }
    }

    public func lookup(docType: String, name: String, field: String) throws -> FieldValue? {
        let key = CacheKey(docType: docType, name: name)

        lock.lock()
        if let row = cache[key], let cached = row[field] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let base = base else { return nil }
        let value = try base.lookup(docType: docType, name: name, field: field)

        lock.lock()
        cache[key, default: [:]][field] = value
        lock.unlock()
        return value
    }

    /// Drop every cached field for a single document.
    public func invalidate(docType: String, name: String) {
        let key = CacheKey(docType: docType, name: name)
        lock.lock()
        cache.removeValue(forKey: key)
        lock.unlock()
    }

    /// Drop the entire cache. Use sparingly — the per-save subscription
    /// keeps the cache coherent without this.
    public func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    /// Total number of cached fields (sum across documents). Test affordance.
    public var cachedFieldCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.values.reduce(0) { $0 + $1.count }
    }

    /// True iff the resolver has a cache entry for the given key.
    /// Test affordance for the per-save invalidation tests.
    public func isCached(docType: String, name: String, field: String) -> Bool {
        let key = CacheKey(docType: docType, name: name)
        lock.lock()
        defer { lock.unlock() }
        return cache[key]?[field] != nil
    }

    private func subscribe(to emitter: EventEmitter) {
        subscriptionTokens.append(emitter.subscribe(DocumentSavedEvent.self) { [weak self] event in
            self?.invalidate(docType: event.docType, name: event.document.id)
        })
        subscriptionTokens.append(emitter.subscribe(DocumentDeletedEvent.self) { [weak self] event in
            self?.invalidate(docType: event.docType, name: event.documentId)
        })
        subscriptionTokens.append(emitter.subscribe(DocumentSubmittedEvent.self) { [weak self] event in
            self?.invalidate(docType: event.docType, name: event.document.id)
        })
        subscriptionTokens.append(emitter.subscribe(DocumentCancelledEvent.self) { [weak self] event in
            self?.invalidate(docType: event.docType, name: event.document.id)
        })
    }
}
