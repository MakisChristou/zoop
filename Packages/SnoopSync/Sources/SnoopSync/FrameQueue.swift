import Foundation
import SQLite3

/// Durable frames. A receipt is the only authority to remove a row. Pre-upgrade
/// rows retain their legacy sequence identity; newly captured rows have UUIDs.
public final class FrameQueue: @unchecked Sendable {
    public struct Row: Sendable {
        public let id: Int64
        public let clientSeq: Int64
        public let uploadId: String?
        public let channel: Int
        public let receivedAt: Date
        public let bytes: [UInt8]
    }
    public struct Resolution {
        public let rowId: Int64
        public let holdReason: String?
        public init(rowId: Int64, holdReason: String? = nil) { self.rowId = rowId; self.holdReason = holdReason }
    }
    private let db: OpaquePointer
    private let lock = NSLock()
    private var closed = false
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path.path, &handle) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw QueueError.sql("Cannot open the frame queue")
        }
        db = handle
        do {
            sqlite3_busy_timeout(db, 5_000)
            try exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
            try exec("""
            CREATE TABLE IF NOT EXISTS frames (
                id INTEGER PRIMARY KEY AUTOINCREMENT, client_seq INTEGER NOT NULL UNIQUE,
                channel INTEGER NOT NULL, received_at REAL NOT NULL, bytes BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS counters (name TEXT PRIMARY KEY, value INTEGER NOT NULL);
            INSERT OR IGNORE INTO counters VALUES ('client_seq', 0);
            """)
            if try scalar("PRAGMA user_version") == 0 {
                try transaction {
                    try exec("ALTER TABLE frames ADD COLUMN upload_id TEXT;")
                    try exec("ALTER TABLE frames ADD COLUMN held_reason TEXT;")
                    try exec("PRAGMA user_version=1;")
                }
            }
        } catch { sqlite3_close(db); closed = true; throw error }
    }
    deinit { if !closed { sqlite3_close(db) } }

    public static func defaultPath() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true).appendingPathComponent("frames.sqlite")
    }

    @discardableResult
    public func enqueue(_ bytes: [UInt8], channel: Int, receivedAt: Date = Date()) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return try transaction {
            try exec("UPDATE counters SET value=value+1 WHERE name='client_seq'")
            let seq = try scalar("SELECT value FROM counters WHERE name='client_seq'")
            let stmt = try prepare("INSERT INTO frames(client_seq,channel,received_at,bytes,upload_id) VALUES(?,?,?,?,?)")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, seq)
            sqlite3_bind_int(stmt, 2, Int32(channel))
            sqlite3_bind_double(stmt, 3, receivedAt.timeIntervalSince1970)
            _ = bytes.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32($0.count), transient) }
            sqlite3_bind_text(stmt, 5, UUID().uuidString.lowercased(), -1, transient)
            try done(stmt)
            return seq
        }
    }

    public func peek(limit: Int) throws -> [Row] {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare("SELECT id,client_seq,channel,received_at,bytes,upload_id FROM frames WHERE held_reason IS NULL ORDER BY id LIMIT ?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var rows: [Row] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { return rows }
            guard step == SQLITE_ROW else { throw QueueError.sql(message()) }
            let count = Int(sqlite3_column_bytes(stmt, 4))
            let bytes = sqlite3_column_blob(stmt, 4).map {
                Array(UnsafeBufferPointer(start: $0.assumingMemoryBound(to: UInt8.self), count: count))
            } ?? []
            rows.append(Row(id: sqlite3_column_int64(stmt, 0), clientSeq: sqlite3_column_int64(stmt, 1),
                uploadId: sqlite3_column_text(stmt, 5).map { String(cString: $0) },
                channel: Int(sqlite3_column_int(stmt, 2)),
                receivedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)), bytes: bytes))
        }
    }

    /// All receipts from one validated response are applied atomically. Held rows
    /// retain their bytes and identity and cannot block healthy rows behind them.
    public func resolve(_ resolutions: [Resolution]) throws {
        lock.lock(); defer { lock.unlock() }
        try transaction {
            for resolution in resolutions {
                let stmt = try prepare(resolution.holdReason == nil ? "DELETE FROM frames WHERE id=?" : "UPDATE frames SET held_reason=? WHERE id=?")
                defer { sqlite3_finalize(stmt) }
                if let reason = resolution.holdReason {
                    sqlite3_bind_text(stmt, 1, reason, -1, transient)
                    sqlite3_bind_int64(stmt, 2, resolution.rowId)
                } else { sqlite3_bind_int64(stmt, 1, resolution.rowId) }
                try done(stmt)
            }
        }
    }
    public func retryHeld() throws {
        lock.lock(); defer { lock.unlock() }
        try exec("UPDATE frames SET held_reason=NULL WHERE held_reason IS NOT NULL")
    }
    public func count() throws -> Int {
        lock.lock(); defer { lock.unlock() }; return Int(try scalar("SELECT count(*) FROM frames"))
    }
    public func heldCount() throws -> Int {
        lock.lock(); defer { lock.unlock() }; return Int(try scalar("SELECT count(*) FROM frames WHERE held_reason IS NOT NULL"))
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do { let value = try body(); try exec("COMMIT"); return value }
        catch { try? exec("ROLLBACK"); throw error }
    }
    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw QueueError.sql(message()) }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw QueueError.sql(message()) }
        return stmt
    }
    private func done(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw QueueError.sql(message()) }
    }
    private func scalar(_ sql: String) throws -> Int64 {
        let stmt = try prepare(sql); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw QueueError.sql(message()) }
        return sqlite3_column_int64(stmt, 0)
    }
    private func message() -> String { String(cString: sqlite3_errmsg(db)) }
}
public enum QueueError: Error, LocalizedError {
    case sql(String)
    public var errorDescription: String? { if case .sql(let message) = self { return message }; return nil }
}
