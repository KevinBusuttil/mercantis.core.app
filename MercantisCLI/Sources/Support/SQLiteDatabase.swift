import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteDatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message), .prepareFailed(let message), .stepFailed(let message), .bindFailed(let message):
            return message
        }
    }
}

final class SQLiteDatabase {
    private var db: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw SQLiteDatabaseError.openFailed("Failed to open database: \(message)")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String) throws {
        try execute(sql, parameters: [])
    }

    func execute(_ sql: String, parameters: [String]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        try bind(parameters, to: statement)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func query(_ sql: String, parameters: [String] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        try bind(parameters, to: statement)

        var rows: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            let columnCount = sqlite3_column_count(statement)

            for index in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(statement, index))
                if let value = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: value)
                } else {
                    row[name] = ""
                }
            }
            rows.append(row)
        }

        return rows
    }

    func tableExists(_ name: String) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
        do {
            let rows = try query(sql, parameters: [name])
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    private func bind(_ parameters: [String], to statement: OpaquePointer?) throws {
        for (index, value) in parameters.enumerated() {
            if sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT) != SQLITE_OK {
                throw SQLiteDatabaseError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
}
