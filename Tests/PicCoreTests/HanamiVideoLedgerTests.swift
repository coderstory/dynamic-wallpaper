import SQLite3
import XCTest
@testable import PicCore

final class HanamiVideoLedgerTests: XCTestCase {

    private var root: URL!
    private var dbURL: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-ledger-\(UUID().uuidString)", isDirectory: true)
        dbURL = root.appendingPathComponent("deleted-videos.sqlite")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        dbURL = nil
        super.tearDown()
    }

    func testRoundTrip() throws {
        let ledger = HanamiVideoLedger(databaseURL: dbURL)
        try ledger.insert("abc")
        XCTAssertTrue(ledger.contains("abc"))
        XCTAssertFalse(ledger.contains("unknown"))
    }

    func testInsertIsIdempotent() throws {
        let ledger = HanamiVideoLedger(databaseURL: dbURL)
        try ledger.insert("dup")
        XCTAssertNoThrow(try ledger.insert("dup"))
        XCTAssertEqual(rowCount(), 1, "同 md5 两次 insert 仍只一行")
    }

    func testCorruptDatabaseDegradesThenRecovers() throws {
        try Data("garbage bytes, not a database".utf8).write(to: dbURL)
        let ledger = HanamiVideoLedger(databaseURL: dbURL)
        XCTAssertFalse(ledger.contains("abc"), "坏库读 → false 不崩")
        XCTAssertNoThrow(try ledger.insert("abc"), "坏库写 → 删文件重建")
        XCTAssertTrue(ledger.contains("abc"), "重建后可用")
    }

    func testPersistsAcrossReopen() throws {
        try HanamiVideoLedger(databaseURL: dbURL).insert("persist")
        XCTAssertTrue(HanamiVideoLedger(databaseURL: dbURL).contains("persist"))
    }

    /// 公开 API 只有 contains，行数判等只能直连数。
    private func rowCount() -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            XCTFail("打不开测试库")
            return -1
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM deleted_video_md5", -1, &stmt, nil) == SQLITE_OK,
              let stmt,
              sqlite3_step(stmt) == SQLITE_ROW else {
            XCTFail("数行查询失败")
            return -1
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }
}
