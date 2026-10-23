import Foundation
import SQLite3

/// Durable local queue of complete frames awaiting upload. Every frame is written here
/// before anything else happens to it; rows are deleted only after the server accepts
/// the batch. `clientSeq` is monotonic per install so the server can de-duplicate.
final class FrameQueue {
    struct Row {
        let id: Int64
        let clientSeq: Int64
        let channel: Int
        let receivedAt: Date
        let bytes: [UInt8]
    }

    private let db: OpaquePointer
    private let lock = NSLock()

    init(path: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path.path, &handle) == SQLITE_OK, let handle else {
            throw QueueError.open(path.path)
        }
        db = handle
        try exec("""
        CREATE TABLE IF NOT EXISTS frames (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            client_seq  INTEGER NOT NULL UNIQUE,
            channel     INTEGER NOT NULL,
            received_at REAL    NOT NULL,
            bytes       BLOB    NOT NULL
        );
        CREATE TABLE IF NOT EXISTS counters (name TEXT PRIMARY KEY, value INTEGER NOT NULL);
        INSERT OR IGNORE INTO counters VALUES ('client_seq', 0);
        """)
    }

    deinit { sqlite3_close(db) }

    static func defaultPath() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("frames.sqlite")
    }

    /// Appends one frame and returns its client sequence number.
    @discardableResult
    func enqueue(_ bytes: [UInt8], channel: Int, receivedAt: Date = Date()) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        try exec("BEGIN")
        do {
            try exec("UPDATE counters SET value = value + 1 WHERE name = 'client_seq'")
            let seq = try scalar("SELECT value FROM counters WHERE name = 'client_seq'")
            let stmt = try prepare("INSERT INTO frames (client_seq, channel, received_at, bytes) VALUES (?, ?, ?, ?)")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, seq)
            sqlite3_bind_int(stmt, 2, Int32(channel))
            sqlite3_bind_double(stmt, 3, receivedAt.timeIntervalSince1970)
            _ = bytes.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32($0.count), nil) }
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw QueueError.sql(message()) }
            try exec("COMMIT")
            return seq
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// Oldest `limit` frames.
    func peek(limit: Int) throws -> [Row] {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare("SELECT id, client_seq, channel, received_at, bytes FROM frames ORDER BY id LIMIT ?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(stmt, 4))
            let blob = sqlite3_column_blob(stmt, 4)
            let bytes = blob.map { Array(UnsafeBufferPointer(start: $0.assumingMemoryBound(to: UInt8.self), count: count)) } ?? []
            rows.append(Row(id: sqlite3_column_int64(stmt, 0),
                            clientSeq: sqlite3_column_int64(stmt, 1),
                            channel: Int(sqlite3_column_int(stmt, 2)),
                            receivedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                            bytes: bytes))
        }
        return rows
    }

    /// Removes rows the server has accepted (or recorded as duplicates).
    func remove(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let stmt = try prepare("DELETE FROM frames WHERE id IN (\(placeholders))")
        defer { sqlite3_finalize(stmt) }
        for (i, id) in ids.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), id) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw QueueError.sql(message()) }
    }

    func count() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return Int(try scalar("SELECT COUNT(*) FROM frames"))
    }

    // MARK: - SQLite helpers

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw QueueError.sql(message()) }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw QueueError.sql(message()) }
        return stmt
    }

    private func scalar(_ sql: String) throws -> Int64 {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw QueueError.sql(message()) }
        return sqlite3_column_int64(stmt, 0)
    }

    private func message() -> String {
        String(cString: sqlite3_errmsg(db))
    }
}

enum QueueError: Error {
    case open(String)
    case sql(String)
}
