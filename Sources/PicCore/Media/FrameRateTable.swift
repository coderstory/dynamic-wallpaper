import Foundation

/// 单个源文件的探测结果与降帧状态。
public struct FrameRateEntry: Codable, Equatable, Sendable {
    public var sourcePath: String
    /// 与 `sourceMtime` 一起构成「还是不是当初那个文件」的判据。
    public var sourceSize: Int
    public var sourceMtime: Date
    public var fps: Double
    public var durationSeconds: Double
    public var derivativePath: String?
    public var derivativeMtime: Date?
    public var state: ProbeState

    public init(sourcePath: String, sourceSize: Int, sourceMtime: Date,
                fps: Double, durationSeconds: Double,
                derivativePath: String? = nil, derivativeMtime: Date? = nil,
                state: ProbeState = .needsProbe) {
        self.sourcePath = sourcePath
        self.sourceSize = sourceSize
        self.sourceMtime = sourceMtime
        self.fps = fps
        self.durationSeconds = durationSeconds
        self.derivativePath = derivativePath
        self.derivativeMtime = derivativeMtime
        self.state = state
    }

    /// 这一行还能信吗。size 与 mtime 都参与：只比 mtime 会漏掉「换成同时间戳的另一个视频」，那种情况下旧帧率会把该转的文件判成不必转。
    public func isValid(against attributes: [FileAttributeKey: Any]) -> Bool {
        guard let size = attributes[.size] as? Int,
              let mtime = attributes[.modificationDate] as? Date else { return false }
        return size == sourceSize && mtime == sourceMtime
    }

    /// 派生文件此刻是否仍可用 —— 被删或被改就回落到原片。
    public func hasLiveDerivative() -> Bool {
        guard let derivativePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: derivativePath),
              let mtime = attributes[.modificationDate] as? Date else { return false }
        guard let derivativeMtime else { return true }
        return mtime == derivativeMtime
    }
}

/// 一行的生命周期。`recovered` 是跨重启的那道闸。
public enum ProbeState: String, Codable, Equatable, Sendable {
    case needsProbe
    /// 源本就 ≤30fps，无需处理。
    case okAt30
    case needsConvert
    case converting
    case done
    case failed

    /// 从磁盘读回时 `converting` / `failed` 退回可重试：没有半个进程在跑，半成品不该被当成「已处理过」而永久跳过。
    public var recovered: ProbeState {
        switch self {
        case .converting, .failed: return .needsConvert
        case .needsProbe, .okAt30, .needsConvert, .done: return self
        }
    }
}

/// 帧率表 —— 单个 JSON 文件。规模在几百行量级，换 sqlite 的收益为零却要引入 C API。形状照 `LaunchAgentWriter`：**写抛、读静默**。
public struct FrameRateTable: Codable, Equatable, Sendable {

    public var entries: [FrameRateEntry]

    public init(entries: [FrameRateEntry] = []) {
        self.entries = entries
    }

    // MARK: - 查询

    /// 路径比统一走 `standardized`：`FileManager.enumerator` 返回的是 `/private/var/...`，而调用方给的可能是 `/var/...` 或 `/Users/...`。直接 `==` 比 path 会永远命中不了 —— 症状是增量扫描静默退化成全量重探。
    public func entry(for source: URL) -> FrameRateEntry? {
        let key = Self.key(for: source)
        return entries.first { Self.key(forPath: $0.sourcePath) == key }
    }

    static func key(for url: URL) -> String { url.standardizedFileURL.path }
    static func key(forPath path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.path }

    /// 增量扫描的判据：能复用就返回，省掉一次 `AVURLAsset` 打开。
    public func reusableEntry(for source: URL) -> FrameRateEntry? {
        guard var entry = entry(for: source) else { return nil }
        entry.state = entry.state.recovered
        guard entry.state != .needsProbe else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: source.path),
              entry.isValid(against: attributes) else { return nil }
        return entry
    }

    public var needsConvertCount: Int {
        entries.filter { $0.state.recovered == .needsConvert }.count
    }

    public var okAt30Count: Int {
        entries.filter { $0.state.recovered == .okAt30 }.count
    }

    // MARK: - 变更（每个口都落盘 —— 只在状态跃迁时调用，不是每 tick）

    public mutating func upsert(_ entry: FrameRateEntry, to url: URL = FrameRateTable.defaultURL()) throws {
        if let index = indexOf(entry.sourcePath) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try save(to: url)
    }

    private func indexOf(_ sourcePath: String) -> Int? {
        let key = Self.key(forPath: sourcePath)
        return entries.firstIndex { Self.key(forPath: $0.sourcePath) == key }
    }

    public mutating func updateState(_ state: ProbeState, for source: URL,
                                     to url: URL = FrameRateTable.defaultURL()) throws {
        guard let index = indexOf(source.path) else { return }
        entries[index].state = state
        if state == .done, let path = entries[index].derivativePath {
            entries[index].derivativeMtime = try? FileManager.default
                .attributesOfItem(atPath: path)[.modificationDate] as? Date
        }
        try save(to: url)
    }

    /// 丢掉源已不存在的行（片库删了文件，表里不能留孤儿）。
    public mutating func prune(keepingLiveSources livePaths: Set<String>,
                               to url: URL = FrameRateTable.defaultURL()) throws {
        let live = Set(livePaths.map(Self.key(forPath:)))
        let before = entries.count
        entries.removeAll { !live.contains(Self.key(forPath: $0.sourcePath)) }
        if entries.count != before { try save(to: url) }
    }

    // MARK: - 落盘

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pic", isDirectory: true)
            .appendingPathComponent("frame-rate-table.json", isDirectory: false)
    }

    public func save(to url: URL = FrameRateTable.defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL = FrameRateTable.defaultURL()) -> FrameRateTable {
        guard let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(FrameRateTable.self, from: data) else {
            return FrameRateTable()
        }
        return table
    }
}