import Foundation

/// `UserDefaults(suiteName:)` 的域文件**不会**因 `removePersistentDomain` 而消失 —— cfprefsd 会把空域
/// 写回磁盘，于是每个用例留一个 plist。实测本机 `~/Library/Preferences/pic.tests.*.plist` 累积到
/// 3000+ 个 / 12M，占 Preferences 目录的九成。
///
/// 这里把内存态与磁盘上的域文件一起清掉。**只碰 `pic.tests.` 前缀**：越界的名字直接返回，
/// 免得哪天 suiteName 命名改了而误删真实偏好。
enum TestDefaults {
    static func purge(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        guard suiteName.hasPrefix("pic.tests.") else { return }
        let path = NSHomeDirectory() + "/Library/Preferences/\(suiteName).plist"
        try? FileManager.default.removeItem(atPath: path)
    }
}
