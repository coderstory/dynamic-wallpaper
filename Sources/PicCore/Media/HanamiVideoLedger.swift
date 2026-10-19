import Foundation
import SQLite3

// SDK 的 SQLite3 模块不导出 SQLITE_STATIC 宏（定义为 ((sqlite3_destructor_type)0)），按字面值补齐：
// 让 SQLite 直接引用传入指针、不拷贝 —— buffer 寿命由调用侧 withCString 保证。
private let SQLITE_STATIC = unsafeBitCast(OpaquePointer(bitPattern: 0), to: sqlite3_destructor_type.self)

/// 已删视频的 MD5 墓碑库 —— 导入时命中即跳过，避免「删一次导一次全回来」。
///
/// **每操作现开现关连接，不持句柄、不加锁 —— 刻意如此，勿重构**：调用点横跨主线程删除钩子
/// 与后台导入 Task；SQLite3 句柄非 Sendable，持句柄就得加锁管生命周期；两类调用都是分钟级
/// 一次，现开现关开销可忽略。墓碑历史可弃：坏库降级（删文件重建）永不拦导入或删除。
public struct HanamiVideoLedger: Sendable {

    /// 写侧拿不到可用库时抛。墓碑缺一条的代价只是「素材多导一次」。
    public enum Error: Swift.Error { case databaseUnavailable }

    private static let schemaSQL = """
        CREATE TABLE IF NOT EXISTS deleted_video_md5 (md5 TEXT PRIMARY KEY, deleted_at REAL NOT NULL)
        """

    private let databaseURL: URL

    public init(databaseURL: URL = HanamiVideoLedger.defaultURL()) {
        self.databaseURL = databaseURL
    }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pic", isDirectory: true)
            .appendingPathComponent("deleted-videos.sqlite", isDirectory: false)
    }

    /// 读静默：任何错 → false（没删过）。
    public func contains(_ md5: String) -> Bool {
        guard let db = open() else { return false }
        defer { sqlite3_close(db) }
        guard let stmt = prepare("SELECT 1 FROM deleted_video_md5 WHERE md5 = ?", on: db) else { return false }
        defer { sqlite3_finalize(stmt) }
        // SQLITE_STATIC 不拷贝：bind 与 step 必须都圈进 withCString，buffer 活不过 step 就是悬垂指针。
        var found = false
        md5.withCString { text in
            guard sqlite3_bind_text(stmt, 1, text, -1, SQLITE_STATIC) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW else { return }
            found = true
        }
        return found
    }

    /// 写抛；`INSERT OR IGNORE` 幂等 —— 重复插入是 no-op 不是错误。
    public func insert(_ md5: String, deletedAt: Date = Date()) throws {
        guard let db = open() else { throw Error.databaseUnavailable }
        defer { sqlite3_close(db) }
        guard let stmt = prepare(
            "INSERT OR IGNORE INTO deleted_video_md5 (md5, deleted_at) VALUES (?, ?)", on: db) else {
            throw Error.databaseUnavailable
        }
        defer { sqlite3_finalize(stmt) }
        // SQLITE_STATIC 不拷贝：bind 与 step 必须都圈进 withCString（step 时才读指针），
        // 漏一半就是悬垂指针 —— 实测症状是静默写入空串。
        var inserted = false
        md5.withCString { text in
            guard sqlite3_bind_text(stmt, 1, text, -1, SQLITE_STATIC) == SQLITE_OK,
                  sqlite3_bind_double(stmt, 2, deletedAt.timeIntervalSince1970) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_DONE else { return }
            inserted = true
        }
        guard inserted else { throw Error.databaseUnavailable }
    }

    /// 打开并确保 schema。坏库降级：首次失败 → 删文件重试一次；仍败回 nil（读 false / 写抛）。
    private func open() -> OpaquePointer? {
        let first = openOnce()
        if let db = first.db { return db }
        // BUSY 是暂时态（对手连接持写锁，busy_timeout 已等过 1s），删库 = 毁掉健康墓碑；
        // 只有坏库（NOTADB 等）才走删库重建。
        guard !first.busy else { return nil }
        // CREATE 不建中间目录：全新机器首跑（FrameRateTable 尚未落盘过）父目录不存在，open 会失败。
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: databaseURL)
        return openOnce().db
    }

    private func openOnce() -> (db: OpaquePointer?, busy: Bool) {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK, let db else {
            let busy = rc == SQLITE_BUSY || (db != nil && sqlite3_errcode(db) == SQLITE_BUSY)
            sqlite3_close(db)
            return (nil, busy)
        }
        // 删除钩子与导入会各开短连接并发写同一库：无超时则 SQLITE_BUSY 让 try? insert 与读静默悄悄失败。
        sqlite3_busy_timeout(db, 1000)
        guard sqlite3_exec(db, Self.schemaSQL, nil, nil, nil) == SQLITE_OK else {
            // errcode 必须赶在 close 前取，close 之后句柄失效。
            let busy = sqlite3_errcode(db) == SQLITE_BUSY
            sqlite3_close(db)
            return (nil, busy)
        }
        return (db, false)
    }

    private func prepare(_ sql: String, on db: OpaquePointer) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            sqlite3_finalize(stmt)
            return nil
        }
        return stmt
    }
}
