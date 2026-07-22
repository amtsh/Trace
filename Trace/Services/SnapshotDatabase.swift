import Foundation
import SQLite3

nonisolated(unsafe) private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor SnapshotDatabase: SnapshotStore {
    nonisolated(unsafe) private var db: OpaquePointer?

    init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Trace", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("trace.db").path

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw DBError.open(db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown")
        }

        let sql = """
            CREATE TABLE IF NOT EXISTS snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                app_bundle TEXT NOT NULL,
                app_name TEXT NOT NULL,
                window_title TEXT,
                doc_url TEXT,
                is_idle INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_snap_ts ON snapshots(timestamp);
        """
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DBError.exec(msg)
        }
    }

    deinit { sqlite3_close(db) }

    // MARK: - SnapshotStore

    func append(_ ctx: CapturedContext) throws {
        let sql = """
            INSERT INTO snapshots
            (timestamp, app_bundle, app_name, window_title, doc_url, is_idle)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        bindText(stmt, 2, ctx.appBundle)
        bindText(stmt, 3, ctx.appName)
        bindText(stmt, 4, ctx.windowTitle)
        bindText(stmt, 5, ctx.documentURL)
        sqlite3_bind_int(stmt, 6, ctx.isIdle ? 1 : 0)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DBError.step(errMsg)
        }
    }

    func fetchSnapshots(since date: Date) throws -> [Snapshot] {
        let sql = """
            SELECT id, timestamp, app_bundle, app_name, window_title, doc_url, is_idle
            FROM snapshots WHERE timestamp >= ? ORDER BY timestamp ASC
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)

        var rows: [Snapshot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(readRow(stmt))
        }
        return rows
    }

    func lastSnapshot() throws -> Snapshot? {
        let sql = """
            SELECT id, timestamp, app_bundle, app_name, window_title, doc_url, is_idle
            FROM snapshots ORDER BY timestamp DESC LIMIT 1
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? readRow(stmt) : nil
    }

    func pruneOlderThan(_ date: Date) throws {
        let stmt = try prepare("DELETE FROM snapshots WHERE timestamp < ?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Helpers

    private func readRow(_ s: OpaquePointer) -> Snapshot {
        Snapshot(
            id: sqlite3_column_int64(s, 0),
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(s, 1)),
            appBundle: col(s, 2) ?? "",
            appName: col(s, 3) ?? "",
            windowTitle: col(s, 4),
            documentURL: col(s, 5),
            isIdle: sqlite3_column_int(s, 6) != 0
        )
    }

    private func col(_ s: OpaquePointer, _ i: Int32) -> String? {
        sqlite3_column_type(s, i) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(s, i))
    }

    private func bindText(_ s: OpaquePointer?, _ i: Int32, _ v: String?) {
        if let v {
            sqlite3_bind_text(s, i, (v as NSString).utf8String, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        } else {
            sqlite3_bind_null(s, i)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(errMsg)
        }
        return stmt!
    }

    private var errMsg: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }
}

enum DBError: Error, LocalizedError {
    case open(String), prepare(String), step(String), exec(String)
    var errorDescription: String? {
        switch self {
        case .open(let m): "DB open failed: \(m)"
        case .prepare(let m): "Prepare failed: \(m)"
        case .step(let m): "Step failed: \(m)"
        case .exec(let m): "Exec failed: \(m)"
        }
    }
}
