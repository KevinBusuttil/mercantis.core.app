//
//  CronExpression.swift
//  mercantis core
//
//  P1.4 — Dependency-free cron expression parser + matcher.
//
//  Supports the five-field cron subset used by Frappe-style scheduler hooks:
//
//      minute  hour  dayOfMonth  month  dayOfWeek
//
//  Each field accepts:
//    - `*`                       — any value
//    - integer                   — exact match
//    - comma-separated list      — `1,15,30`
//    - inclusive range           — `9-17`
//    - step                      — `*/5` or `0-30/2`
//
//  Day-of-week is `0` (Sunday) through `6` (Saturday). `7` is also accepted
//  as an alias for Sunday (Vixie-cron compatibility).
//
//  Aliases like `@yearly`, `@daily`, `@reboot` are intentionally NOT
//  supported — `ScheduleInterval` already exposes `.daily` / `.hourly` /
//  `.monthly` for those cases, and accepting both forms here would just
//  duplicate the matrix.
//

import Foundation

/// A parsed cron expression. (P1.4, §4.13)
///
/// Use `CronExpression.parse(_:)` to build one; `matches(_:in:)` returns
/// whether a given `Date` (taken to the nearest minute) satisfies all five
/// fields. `nextFireDate(after:in:)` walks forward minute-by-minute until
/// it finds the next match — sufficient for the launch + every-60-seconds
/// due-check the scheduler performs, while staying small enough to read.
public struct CronExpression: Equatable, Sendable {

    public let minutes: Set<Int>           // 0..59
    public let hours: Set<Int>             // 0..23
    public let daysOfMonth: Set<Int>       // 1..31
    public let months: Set<Int>            // 1..12
    public let daysOfWeek: Set<Int>        // 0..6  (Sunday == 0)

    /// True when both day-of-month and day-of-week were specified explicitly
    /// (i.e. neither is `*`). Vixie-cron treats this as an OR rather than
    /// AND — a tick fires when *either* matches. Kept here so the matcher
    /// can apply that rule and the parser stays the single source of truth.
    public let dayFieldsAreUnion: Bool

    public init(
        minutes: Set<Int>,
        hours: Set<Int>,
        daysOfMonth: Set<Int>,
        months: Set<Int>,
        daysOfWeek: Set<Int>,
        dayFieldsAreUnion: Bool
    ) {
        self.minutes = minutes
        self.hours = hours
        self.daysOfMonth = daysOfMonth
        self.months = months
        self.daysOfWeek = daysOfWeek
        self.dayFieldsAreUnion = dayFieldsAreUnion
    }

    // MARK: - Parsing

    public enum ParseError: Error, Equatable, Sendable {
        case wrongFieldCount(expected: Int, found: Int, expression: String)
        case invalidField(field: String, reason: String)
        case stepNotPositive(field: String)
        case rangeInverted(field: String)
        case valueOutOfRange(field: String, value: Int, min: Int, max: Int)
    }

    /// Parse a 5-field cron expression. Whitespace between fields collapses;
    /// leading / trailing whitespace is ignored.
    public static func parse(_ expression: String) throws -> CronExpression {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard fields.count == 5 else {
            throw ParseError.wrongFieldCount(
                expected: 5,
                found: fields.count,
                expression: expression
            )
        }

        let minutes = try parseField(fields[0], min: 0, max: 59)
        let hours   = try parseField(fields[1], min: 0, max: 23)
        let dom     = try parseField(fields[2], min: 1, max: 31)
        let months  = try parseField(fields[3], min: 1, max: 12)

        // Day-of-week parses with extended range so `7` is accepted, then
        // normalised to `0` (Sunday).
        let dowRaw  = try parseField(fields[4], min: 0, max: 7)
        var dow: Set<Int> = []
        for v in dowRaw {
            dow.insert(v == 7 ? 0 : v)
        }

        let dayFieldsAreUnion = (fields[2] != "*") && (fields[4] != "*")

        return CronExpression(
            minutes: minutes,
            hours: hours,
            daysOfMonth: dom,
            months: months,
            daysOfWeek: dow,
            dayFieldsAreUnion: dayFieldsAreUnion
        )
    }

    private static func parseField(
        _ raw: String,
        min low: Int,
        max high: Int
    ) throws -> Set<Int> {
        var values: Set<Int> = []
        // Comma splits a list of sub-expressions; each is parsed independently.
        for piece in raw.split(separator: ",").map(String.init) {
            try expand(
                piece: piece,
                fieldName: raw,
                low: low,
                high: high,
                into: &values
            )
        }
        if values.isEmpty {
            throw ParseError.invalidField(field: raw, reason: "empty after expansion")
        }
        return values
    }

    private static func expand(
        piece: String,
        fieldName: String,
        low: Int,
        high: Int,
        into values: inout Set<Int>
    ) throws {
        // Step syntax: `expr/step`. Step on its own is illegal; expr defaults
        // to the full range when piece starts with `*/N`.
        var base = piece
        var step = 1

        if let slash = piece.firstIndex(of: "/") {
            base = String(piece[..<slash])
            let stepStr = String(piece[piece.index(after: slash)...])
            guard let parsedStep = Int(stepStr), parsedStep > 0 else {
                throw ParseError.stepNotPositive(field: fieldName)
            }
            step = parsedStep
        }

        let (lo, hi): (Int, Int)
        if base == "*" {
            lo = low
            hi = high
        } else if let dash = base.firstIndex(of: "-") {
            let loStr = String(base[..<dash])
            let hiStr = String(base[base.index(after: dash)...])
            guard let loVal = Int(loStr), let hiVal = Int(hiStr) else {
                throw ParseError.invalidField(field: fieldName, reason: "non-integer range bounds in '\(base)'")
            }
            guard loVal <= hiVal else {
                throw ParseError.rangeInverted(field: fieldName)
            }
            lo = loVal
            hi = hiVal
        } else {
            guard let exact = Int(base) else {
                throw ParseError.invalidField(field: fieldName, reason: "non-integer value '\(base)'")
            }
            lo = exact
            hi = exact
        }

        guard lo >= low, hi <= high else {
            throw ParseError.valueOutOfRange(
                field: fieldName,
                value: lo < low ? lo : hi,
                min: low,
                max: high
            )
        }

        var v = lo
        while v <= hi {
            values.insert(v)
            v += step
        }
    }

    // MARK: - Matching

    /// True when `date` (truncated to the minute) satisfies every field.
    public func matches(_ date: Date, in calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        let comps = calendar.dateComponents(
            [.minute, .hour, .day, .month, .weekday],
            from: date
        )
        guard
            let minute  = comps.minute,
            let hour    = comps.hour,
            let day     = comps.day,
            let month   = comps.month,
            let weekday = comps.weekday    // 1..7, Sunday == 1
        else { return false }

        guard minutes.contains(minute) else { return false }
        guard hours.contains(hour) else { return false }
        guard months.contains(month) else { return false }

        let dowMatches = daysOfWeek.contains(weekday - 1)
        let domMatches = daysOfMonth.contains(day)

        if dayFieldsAreUnion {
            return dowMatches || domMatches
        }
        return dowMatches && domMatches
    }

    /// Walk minute-by-minute starting one minute after `from` until a match
    /// is found. Returns `nil` after `cap` ticks (defaults to one year of
    /// minutes — large enough that any valid cron expression matches at
    /// least once, small enough to bound a runaway loop on a malformed but
    /// parseable expression like `0 0 31 2 *`).
    public func nextFireDate(
        after from: Date,
        in calendar: Calendar = Calendar(identifier: .gregorian),
        cap: Int = 60 * 24 * 366
    ) -> Date? {
        // Truncate to the minute, then start scanning at the next minute.
        var probe: Date = {
            let comps = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: from
            )
            let truncated = calendar.date(from: comps) ?? from
            return calendar.date(byAdding: .minute, value: 1, to: truncated) ?? from
        }()

        var ticks = 0
        while ticks < cap {
            if matches(probe, in: calendar) { return probe }
            guard let next = calendar.date(byAdding: .minute, value: 1, to: probe) else {
                return nil
            }
            probe = next
            ticks += 1
        }
        return nil
    }
}

