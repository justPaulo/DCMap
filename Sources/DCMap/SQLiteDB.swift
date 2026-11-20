import Foundation
import SQLite3

enum DBValue {
    case null
    case int(Int64)
    case double(Double)
    case text(String)

    var int64: Int64? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int64(v)
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
    var string: String {
        switch self {
        case .text(let s): return s
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .null: return ""
        }
    }

    static func optional(_ v: Double?) -> DBValue { v.map { .double($0) } ?? .null }
}

struct DBError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper around the system SQLite3 C API. Not thread-safe: use from one actor/thread.
final class SQLiteDB {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw DBError(message: "Cannot open database: \(msg)")
        }
        try exec("PRAGMA foreign_keys = ON;")
        try exec("PRAGMA journal_mode = WAL;")
    }

    deinit { sqlite3_close(handle) }

    private var lastMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? lastMessage
            sqlite3_free(err)
            throw DBError(message: msg)
        }
    }

    private func prepare(_ sql: String, _ binds: [DBValue]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DBError(message: lastMessage)
        }
        guard let s = stmt else { throw DBError(message: "Could not prepare statement") }
        for (i, b) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch b {
            case .null: sqlite3_bind_null(s, idx)
            case .int(let v): sqlite3_bind_int64(s, idx, v)
            case .double(let v): sqlite3_bind_double(s, idx, v)
            case .text(let v): sqlite3_bind_text(s, idx, v, -1, SQLITE_TRANSIENT)
            }
        }
        return s
    }

    /// Runs INSERT/UPDATE/DELETE. Returns the number of changed rows.
    @discardableResult
    func run(_ sql: String, _ binds: [DBValue] = []) throws -> Int {
        let s = try prepare(sql, binds)
        defer { sqlite3_finalize(s) }
        let rc = sqlite3_step(s)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw DBError(message: lastMessage) }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ binds: [DBValue] = []) throws -> [[DBValue]] {
        let s = try prepare(sql, binds)
        defer { sqlite3_finalize(s) }
        var rows: [[DBValue]] = []
        while true {
            let rc = sqlite3_step(s)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw DBError(message: lastMessage) }
            var row: [DBValue] = []
            for c in 0..<sqlite3_column_count(s) {
                switch sqlite3_column_type(s, c) {
                case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(s, c)))
                case SQLITE_FLOAT: row.append(.double(sqlite3_column_double(s, c)))
                case SQLITE_TEXT:
                    if let p = sqlite3_column_text(s, c) { row.append(.text(String(cString: p))) } else { row.append(.null) }
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }

    var lastInsertID: Int64 { sqlite3_last_insert_rowid(handle) }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try exec("COMMIT;")
            return result
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }
}
