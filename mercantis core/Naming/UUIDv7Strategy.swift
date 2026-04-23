//
//  UUIDv7Strategy.swift
//  mercantis core
//
//  P1.1 / ADR-014 — Default offline-safe naming strategy.
//

import Foundation

/// Generates a RFC 9562 UUID v7 — 48 bits of Unix-millisecond timestamp
/// followed by 74 bits of cryptographically secure randomness (with version
/// and variant bits fixed in between). Time-ordered and globally unique, so
/// it is safe for concurrent offline creation across devices.
///
/// Recommended as the default when no business-readable ID is required.
public struct UUIDv7Strategy: NamingStrategy {

    public var handles: Set<String> { ["uuid", "uuidv7"] }

    public init() {}

    public func resolve(
        docType: DocType,
        document: Document,
        argument: String?,
        context: NamingContext
    ) throws -> String {
        Self.generate(at: context.now)
    }

    /// Produce a UUID v7 string (lower-case, hyphenated 8-4-4-4-12).
    public static func generate(at date: Date = Date()) -> String {
        let milliseconds = UInt64(max(0, date.timeIntervalSince1970) * 1000)

        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = UInt8((milliseconds >> 40) & 0xff)
        bytes[1] = UInt8((milliseconds >> 32) & 0xff)
        bytes[2] = UInt8((milliseconds >> 24) & 0xff)
        bytes[3] = UInt8((milliseconds >> 16) & 0xff)
        bytes[4] = UInt8((milliseconds >> 8) & 0xff)
        bytes[5] = UInt8(milliseconds & 0xff)

        for i in 6..<16 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        // Version 7 in the top 4 bits of byte 6.
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        // Variant 10 in the top 2 bits of byte 8.
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return String(
            format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
    }
}
