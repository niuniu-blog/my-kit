import Foundation
import SQLite3

struct SQLiteError: Error, CustomStringConvertible {
    let code: Int32
    let message: String
    var description: String { "SQLite error \(code): \(message)" }
}

enum SQLiteValue {
    case text(String)
    case double(Double)
    case int(Int64)
    case null
}

/// 查询结果的一行。只在 query 的 map 闭包内有效。
struct SQLiteRow {
    fileprivate let statement: OpaquePointer

    func string(_ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    func int64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    func double(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite3 C API 的最小包装。本身不做线程同步，由持有它的 actor 保证串行访问。
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close_v2(handle)
            handle = nil
            throw SQLiteError(code: rc, message: message)
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    /// 执行一段不带参数的 SQL（可含多条语句），用于建表。
    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(errorMessage)
            throw SQLiteError(code: rc, message: message)
        }
    }

    /// 执行一条带参数的写语句，返回受影响的行数。
    @discardableResult
    func run(_ sql: String, _ params: [SQLiteValue] = []) throws -> Int {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw lastError(rc) }
        return Int(sqlite3_changes(handle))
    }

    func query<T>(_ sql: String, _ params: [SQLiteValue] = [], map: (SQLiteRow) -> T) throws -> [T] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                rows.append(map(SQLiteRow(statement: statement)))
            } else if rc == SQLITE_DONE {
                return rows
            } else {
                throw lastError(rc)
            }
        }
    }

    private func prepare(_ sql: String, _ params: [SQLiteValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else { throw lastError(rc) }
        for (offset, param) in params.enumerated() {
            let index = Int32(offset + 1)
            let bindResult: Int32
            switch param {
            case .text(let value): bindResult = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .double(let value): bindResult = sqlite3_bind_double(statement, index, value)
            case .int(let value): bindResult = sqlite3_bind_int64(statement, index, value)
            case .null: bindResult = sqlite3_bind_null(statement, index)
            }
            guard bindResult == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw lastError(bindResult)
            }
        }
        return statement
    }

    private func lastError(_ code: Int32) -> SQLiteError {
        SQLiteError(code: code, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown")
    }
}
