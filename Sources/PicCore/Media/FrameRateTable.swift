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


    public mutating func upsert(_ entry: FrameRateEntry, to url: URL = FrameRateTable.defaultURL()) throws {
        upsertInMemory(entry)
        try save(to: url)
    }

    /// 只改内存、不落盘。批量探测（`FpsTranscodeQueue.scan` 每文件调一次）时用这个，
    /// 循环结束后由调用方 `save` 一次 —— 否则 500 个文件 = 500 次全量 JSON 编码 + 原子写。
    public mutating func upsertInMemory(_ entry: FrameRateEntry) {
        if let index = indexOf(entry.sourcePath) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
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


    /// 与磁盘对账：「源 ↔ 产物」的关系重建口。
    ///
    /// 产物路径由 `<Converted>/<stem>-30fps.mp4` 唯一确定，**不需要表记住它** ——
    /// 所以卸载重装（表丢了/被重置）、一次写入被覆盖、`Converted/` 被手工删过，
    /// 都能用这一条把关系认回来。缺了它，已经降过帧的文件会重新进队列再烤一遍，
    /// 而且播放池不再做一对一替换，同一段素材被播两次。
    ///
    /// 只动 `.needsConvert ↔ .done` 这一对：`.okAt30` 的行没有产物可对，抬它成 `.done`
    /// 会让「无需处理」的计数凭空少一截。`.needsProbe` 同理 —— 帧率都还没探出来，
    /// 磁盘上的同名产物有可能是别的东西留下的。
    public mutating func reconcileWithDerivatives(to url: URL = FrameRateTable.defaultURL()) throws {
        var changed = false
        for index in entries.indices {
            guard let path = entries[index].derivativePath,
                  entries[index].state != .needsProbe else { continue }
            if let mtime = Self.modificationDate(atPath: path) {
                guard entries[index].state == .needsConvert else { continue }
                entries[index].state = .done
                // `.done` 必须带上产物 mtime —— `hasLiveDerivative` 靠它判「还是不是当初那个产物」。
                entries[index].derivativeMtime = mtime
                changed = true
            } else if entries[index].state == .done {
                entries[index].state = .needsConvert
                entries[index].derivativeMtime = nil
                changed = true
            }
        }
        if changed { try save(to: url) }
    }

    private static func modificationDate(atPath path: String) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

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