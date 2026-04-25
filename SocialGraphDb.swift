import Foundation
import SQLite3

/// Per-account SQLite store for the social graph adjacency (`pubkey` → set of follower
/// pubkeys among the user's first-degree follows). Mirrors the Android `SocialGraphDb`.
/// File lives at `Application Support/wisp/social_graph_<pubkey>.db`. The pubkey is the
/// active user's hex pubkey, so multi-account is just multi-file.
///
/// The full table is rebuilt from scratch on every successful compute (`clear()` then
/// streaming `insertBatch` calls in 5000-row transactions). Reads are infrequent and
/// only target the ~80 nodes shown on the social graph viz.
final class SocialGraphDb {
    private var db: OpaquePointer?
    private let pubkey: String
    private let path: String

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(pubkey: String) throws {
        self.pubkey = pubkey
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("wisp", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.path = support.appendingPathComponent("social_graph_\(pubkey).db").path

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw NSError(domain: "SocialGraphDb", code: 1, userInfo: [NSLocalizedDescriptionKey: "sqlite3_open: \(msg)"])
        }

        try exec("""
            CREATE TABLE IF NOT EXISTS followed_by (
                pubkey TEXT NOT NULL,
                follower TEXT NOT NULL,
                PRIMARY KEY (pubkey, follower)
            ) WITHOUT ROWID;
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_followed_by_pubkey ON followed_by(pubkey);")
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA synchronous = NORMAL;")
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    func clear() throws {
        try exec("DELETE FROM followed_by;")
    }

    /// Insert `(pubkey, follower)` pairs in a single transaction. Duplicates are silently
    /// ignored via `INSERT OR IGNORE` (the PK enforces uniqueness).
    func insertBatch(_ rows: [(pubkey: String, follower: String)]) throws {
        guard !rows.isEmpty else { return }
        try exec("BEGIN;")
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO followed_by (pubkey, follower) VALUES (?, ?);", -1, &stmt, nil) == SQLITE_OK else {
            try? exec("ROLLBACK;")
            throw err("prepare insert")
        }
        for row in rows {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, row.pubkey, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, row.follower, -1, Self.SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                try? exec("ROLLBACK;")
                throw err("step insert")
            }
        }
        try exec("COMMIT;")
    }

    /// All first-degree followers of `pubkey` recorded in the table.
    func getFollowers(_ pubkey: String) -> [String] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT follower FROM followed_by WHERE pubkey = ?;", -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(stmt, 1, pubkey, -1, Self.SQLITE_TRANSIENT)
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cstr = sqlite3_column_text(stmt, 0) {
                out.append(String(cString: cstr))
            }
        }
        return out
    }

    func getFollowerCount(_ pubkey: String) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM followed_by WHERE pubkey = ?;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_text(stmt, 1, pubkey, -1, Self.SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Private

    private func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw NSError(domain: "SocialGraphDb", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "sqlite_exec: \(msg) (sql: \(sql))"])
        }
    }

    private func err(_ where_: String) -> NSError {
        let msg = String(cString: sqlite3_errmsg(db))
        return NSError(domain: "SocialGraphDb", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(where_): \(msg)"])
    }
}
