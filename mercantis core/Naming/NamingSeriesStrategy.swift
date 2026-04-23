//
//  NamingSeriesStrategy.swift
//  mercantis core
//
//  P1.1 / ADR-014 — Sequential series naming (e.g. SINV-2026-00001).
//

import Foundation

/// Resolves a document's ID from a pattern like `SINV-.YYYY.-.####`.
///
/// Pattern syntax follows Frappe's convention: `.TOKEN.` brackets a token.
/// Splitting by `.` yields alternating literal and token segments — even
/// indices are literals, odd indices are tokens.
///
/// Supported tokens (case-sensitive):
/// - `YYYY`, `YY` — 4- or 2-digit year, resolved from `context.now` in the
///   current calendar's timezone (ERP-friendly; local fiscal year wins over UTC).
/// - `MM`, `DD` — 2-digit month / day of month.
/// - `#+` (one or more `#`) — counter, zero-padded to the number of `#`s.
///
/// Exactly one counter token is required. The counter's namespace is the
/// expanded prefix **before** the counter token, scoped by DocType
/// (e.g. `"SalesInvoice::SINV-2026-"`). Counters reset naturally when the
/// expanded prefix rolls over — there is no separate reset policy to configure.
///
/// **Counter-gap note.** The counter is reserved before `DocumentEngine.save`
/// runs the validation pipeline and write transaction. If validation or the
/// write fails, the reserved number is not rolled back; the sequence gains a
/// gap. This matches Frappe / ERPnext behavior and keeps the counter reservation
/// cheap (no long-held locks).
public struct NamingSeriesStrategy: NamingStrategy {

    public var handles: Set<String> { ["naming_series"] }

    public init() {}

    public func resolve(
        docType: DocType,
        document: Document,
        argument: String?,
        context: NamingContext
    ) throws -> String {
        guard let pattern = argument, !pattern.isEmpty else {
            throw NamingError.invalidNamingSeries(
                pattern: argument ?? "",
                reason: "empty pattern"
            )
        }

        let parts = pattern.components(separatedBy: ".")

        // Build the prefix (everything up to the counter token), identify the
        // counter width, and collect the tail (everything after the counter).
        var prefix = ""
        var counterWidth = 0
        var tail: [(index: Int, value: String)] = []
        var counterIndex: Int? = nil

        for (i, part) in parts.enumerated() {
            let isToken = (i % 2 == 1)
            if counterIndex == nil {
                if !isToken {
                    prefix += part
                } else if isCounterToken(part) {
                    counterIndex = i
                    counterWidth = part.count
                } else {
                    prefix += try expandDateToken(
                        part,
                        now: context.now,
                        pattern: pattern
                    )
                }
            } else {
                // After the counter, buffer literals and tokens to expand later.
                tail.append((i, part))
            }
        }

        guard counterIndex != nil else {
            throw NamingError.invalidNamingSeries(
                pattern: pattern,
                reason: "missing counter token (use e.g. .####.)"
            )
        }

        let seriesKey = "\(docType.id)::\(prefix)"
        let counter = try context.counterProvider(seriesKey)
        let counterString = String(format: "%0\(counterWidth)d", counter)

        var result = prefix + counterString
        for (i, part) in tail {
            let isToken = (i % 2 == 1)
            if isToken {
                if isCounterToken(part) {
                    throw NamingError.invalidNamingSeries(
                        pattern: pattern,
                        reason: "multiple counter tokens"
                    )
                }
                result += try expandDateToken(part, now: context.now, pattern: pattern)
            } else {
                result += part
            }
        }
        return result
    }

    private func isCounterToken(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { $0 == "#" }
    }

    private func expandDateToken(
        _ token: String,
        now: Date,
        pattern: String
    ) throws -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: now
        )
        switch token {
        case "YYYY":
            return String(format: "%04d", components.year ?? 0)
        case "YY":
            return String(format: "%02d", (components.year ?? 0) % 100)
        case "MM":
            return String(format: "%02d", components.month ?? 0)
        case "DD":
            return String(format: "%02d", components.day ?? 0)
        default:
            throw NamingError.invalidNamingSeries(
                pattern: pattern,
                reason: "unknown token '\(token)'"
            )
        }
    }
}
