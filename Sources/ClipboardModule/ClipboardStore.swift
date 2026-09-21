import CryptoKit
import Foundation

/// 剪切板历史的持久化。actor 保证所有数据库访问串行执行。
public actor ClipboardStore {
    public enum Location {
        case inMemory
        case file(URL)
    }

    private let db: SQLiteDatabase

    public init(location: Location) throws {
        switch location {
        case .inMemory:
            db = try SQLiteDatabase(path: ":memory:")
        case .file(let url):
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try SQLiteDatabase(path: url.path)
        }
        try Self.migrate(db)
    }

    /// 打开数据库；打不开（文件损坏）时把旧文件改名备份并新建。recovered 为 true 表示发生过重建。
    public static func openRecovering(at url: URL, now: Date = Date()) throws -> (store: ClipboardStore, recovered: Bool) {
        do {
            return (try ClipboardStore(location: .file(url)), false)
        } catch {
            let fileManager = FileManager.default
            let backupName = "\(url.lastPathComponent).corrupt-\(Int(now.timeIntervalSince1970))"
            let backup = url.deletingLastPathComponent().appendingPathComponent(backupName)
            try? fileManager.moveItem(at: url, to: backup)
            for suffix in ["-wal", "-shm"] {
                try? fileManager.removeItem(atPath: url.path + suffix)
            }
            return (try ClipboardStore(location: .file(url)), true)
        }
    }

    private static func migrate(_ db: SQLiteDatabase) throws {
        try db.execute("""
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS items (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            text         TEXT NOT NULL,
            text_hash    TEXT NOT NULL UNIQUE,
            app_bundle   TEXT,
            app_name     TEXT,
            created_at   REAL NOT NULL,
            last_used_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_items_last_used ON items(last_used_at DESC);
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
            text, content='items', content_rowid='id', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
            INSERT INTO items_fts(rowid, text) VALUES (new.id, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
            INSERT INTO items_fts(items_fts, rowid, text) VALUES ('delete', old.id, old.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE OF text ON items BEGIN
            INSERT INTO items_fts(items_fts, rowid, text) VALUES ('delete', old.id, old.text);
            INSERT INTO items_fts(rowid, text) VALUES (new.id, new.text);
        END;
        """)
    }

    /// 新文本 → 插入；已存在的文本 → 只更新时间和来源 App（移到最前）。返回记录 id。
    @discardableResult
    public func add(text: String, appBundleID: String?, appName: String?, at date: Date = Date()) throws -> Int64 {
        let hash = Self.hash(text)
        let timestamp = date.timeIntervalSince1970
        let existing = try db.query("SELECT id FROM items WHERE text_hash = ?", [.text(hash)]) { $0.int64(0) }
        if let id = existing.first {
            try db.run(
                "UPDATE items SET last_used_at = ?, app_bundle = ?, app_name = ? WHERE id = ?",
                [.double(timestamp), Self.optional(appBundleID), Self.optional(appName), .int(id)]
            )
            return id
        }
        try db.run(
            "INSERT INTO items (text, text_hash, app_bundle, app_name, created_at, last_used_at) VALUES (?, ?, ?, ?, ?, ?)",
            [.text(text), .text(hash), Self.optional(appBundleID), Self.optional(appName), .double(timestamp), .double(timestamp)]
        )
        return db.lastInsertRowID
    }

    /// 只把已有记录移到最前（MyKit 自己粘贴时用）。记录不存在返回 false，不会插入。
    @discardableResult
    public func touch(text: String, at date: Date = Date()) throws -> Bool {
        let changed = try db.run(
            "UPDATE items SET last_used_at = ? WHERE text_hash = ?",
            [.double(date.timeIntervalSince1970), .text(Self.hash(text))]
        )
        return changed > 0
    }

    /// 空查询 → 全部；≥3 个字符 → FTS5 trigram；1–2 个字符 → LIKE。一律按最近使用时间倒序。
    public func search(query: String, limit: Int, offset: Int) throws -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let columns = "id, text, app_bundle, app_name, created_at, last_used_at"
        let order = "ORDER BY last_used_at DESC, id DESC LIMIT ? OFFSET ?"
        let paging: [SQLiteValue] = [.int(Int64(limit)), .int(Int64(offset))]

        if trimmed.isEmpty {
            return try db.query("SELECT \(columns) FROM items \(order)", paging, map: Self.item)
        }
        if trimmed.count >= 3 {
            let phrase = "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            return try db.query(
                "SELECT \(columns) FROM items WHERE id IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?) \(order)",
                [.text(phrase)] + paging,
                map: Self.item
            )
        }
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return try db.query(
            "SELECT \(columns) FROM items WHERE text LIKE ? ESCAPE '\\' \(order)",
            [.text("%\(escaped)%")] + paging,
            map: Self.item
        )
    }

    public func delete(id: Int64) throws {
        try db.run("DELETE FROM items WHERE id = ?", [.int(id)])
    }

    public func clearAll() throws {
        try db.run("DELETE FROM items")
    }

    /// 删除最近使用时间早于 cutoff 的记录，返回删除条数。
    @discardableResult
    public func purge(olderThan cutoff: Date) throws -> Int {
        try db.run("DELETE FROM items WHERE last_used_at < ?", [.double(cutoff.timeIntervalSince1970)])
    }

    public func count() throws -> Int {
        let rows = try db.query("SELECT COUNT(*) FROM items") { Int($0.int64(0)) }
        return rows.first ?? 0
    }

    private static func item(_ row: SQLiteRow) -> ClipboardItem {
        ClipboardItem(
            id: row.int64(0),
            text: row.string(1) ?? "",
            appBundleID: row.string(2),
            appName: row.string(3),
            createdAt: Date(timeIntervalSince1970: row.double(4)),
            lastUsedAt: Date(timeIntervalSince1970: row.double(5))
        )
    }

    private static func optional(_ value: String?) -> SQLiteValue {
        value.map(SQLiteValue.text) ?? .null
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
