import Foundation
import OSLog
import SQLite3

nonisolated(unsafe) private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor SnapshotDatabase: SessionPersisting {
    nonisolated(unsafe) private var db: OpaquePointer?

    init() throws {
        try self.init(databaseURL: Self.defaultDatabaseURL())
    }

    init(databaseURL: URL) throws {
        let path = databaseURL.path
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Logger.db.error("Open failed at \(path, privacy: .public): \(message, privacy: .public)")
            throw DatabaseError.openFailed(message)
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
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            Logger.db.error("Schema init failed: \(message, privacy: .public)")
            throw DatabaseError.execFailed(message)
        }

        Logger.db.info("Opened database at \(path, privacy: .public)")
    }

    deinit { sqlite3_close(db) }

    // MARK: - SessionPersisting

    func save(_ snapshot: CapturedContext) throws {
        let sql = """
            INSERT INTO snapshots
            (timestamp, app_bundle, app_name, window_title, doc_url, is_idle)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, snapshot.timestamp.timeIntervalSince1970)
        bindText(stmt, 2, snapshot.appBundle)
        bindText(stmt, 3, snapshot.appName)
        bindText(stmt, 4, snapshot.windowTitle)
        bindText(stmt, 5, snapshot.documentURL)
        sqlite3_bind_int(stmt, 6, snapshot.isIdle ? 1 : 0)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            Logger.db.error("Insert failed: \(self.errMsg, privacy: .public)")
            throw DatabaseError.writeFailed(errMsg)
        }

        Logger.db.debug("Saved snapshot for \(snapshot.appName, privacy: .public)")
    }

    func load(since date: Date) throws -> [Snapshot] {
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
        Logger.db.debug("Loaded \(rows.count) snapshots since cutoff")
        return rows
    }

    func load(afterId id: Int64) throws -> [Snapshot] {
        let sql = """
            SELECT id, timestamp, app_bundle, app_name, window_title, doc_url, is_idle
            FROM snapshots WHERE id > ? ORDER BY timestamp ASC
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)

        var rows: [Snapshot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(readRow(stmt))
        }
        Logger.db.debug("Loaded \(rows.count) snapshots after id \(id)")
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

    func prune(before date: Date) throws {
        let stmt = try prepare("DELETE FROM snapshots WHERE timestamp < ?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            Logger.db.error("Prune failed: \(self.errMsg, privacy: .public)")
            throw DatabaseError.writeFailed(errMsg)
        }

        let deleted = sqlite3_changes(db)
        if deleted > 0 {
            Logger.db.info("Pruned \(deleted) snapshots before cutoff")
        }

        if deleted >= 500 {
            Logger.db.info("Running VACUUM after deleting \(deleted) rows")
            try vacuum()
        }
    }

    // MARK: - Helpers

    private static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Trace", isDirectory: true)
            .appendingPathComponent("trace.db")
    }

    private func vacuum() throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, "VACUUM", nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? errMsg
            sqlite3_free(err)
            Logger.db.error("VACUUM failed: \(message, privacy: .public)")
            throw DatabaseError.execFailed(message)
        }
    }

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
            throw DatabaseError.prepareFailed(errMsg)
        }
        return stmt!
    }

    private var errMsg: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }
}
