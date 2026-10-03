// RotationWiringDriver.swift —— Plan 04-05 T3 的一次性 throwaway 驱动。
//
// 与产品源码一起编译（scripts/probe-rotation-wiring.sh 做这件事）：证据跑的是
// 产品代码，不是探针里重写一遍的逻辑。
//
// 纪律：
//   ① 每行一个数/一个布尔，不合并（D-17）；
//   ② 日志零媒体文件名 / 零路径（T-03-02）—— 记录端只出计数与 ok/bad；
//   ③ 不起真定时器（调度器用文件内 Noop），全部用 advanceNow() 驱动；
//   ④ 本驱动只证 PicCore 侧的「轮换 → 装载」链；AppDelegate 的启动序列
//      （SC4 的应用级路径）需要真实启动一次 app 才能证，当前屏幕锁着，
//      本 Phase 不采集，登记为 Phase 7 的活 —— 如实标 informational。

import Foundation

/// 记录式装载端：只记 URL 的个数与顺序，不记文件名。
final class RecordingLoader: VideoLoading {
    private(set) var loaded: [URL] = []
    func loadPlayback(url: URL) { loaded.append(url) }
}

/// 不触发的调度器（本驱动不需要到点回调驱动）。
final class NoopScheduler: RotationScheduling {
    func schedule(after interval: TimeInterval, _ body: @escaping () -> Void) {}
    func cancel() {}
}

@main
struct RotationWiringDriver {
    @MainActor
    static func main() async {
        func emit(_ line: String) {
            print(line)
            fflush(stdout)
        }

        // 三条人造条目（临时目录拼接，不用媒体语料；日志只出计数）。
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-0405-driver", isDirectory: true)
        let items = (0..<3).map { VideoItem(url: tmp.appendingPathComponent("item\($0)")) }
        emit("PIC_ROT_EVIDENCE items=\(items.count)")

        // 1) .loopSingle：start 装首条 + 3 次 advanceNow（都回 items[0]）→ 4 次。
        let single = RotationController(scheduler: NoopScheduler(),
                                        random: SeededRandomSource(seed: 42))
        let singleLoader = RecordingLoader()
        let singleRouter = PlaybackRouter(rotation: single, loader: singleLoader)
        single.setMode(.loopSingle)
        singleRouter.start(with: items)
        for _ in 0..<3 { singleRouter.advanceNow() }
        emit("PIC_ROT_LOOPSINGLE_LOADS=\(singleLoader.loaded.count)")

        // 2) .loopList：装载顺序恰为 [0,1,2,0]。
        let list = RotationController(scheduler: NoopScheduler(),
                                      random: SeededRandomSource(seed: 42))
        let listLoader = RecordingLoader()
        let listRouter = PlaybackRouter(rotation: list, loader: listLoader)
        list.setMode(.loopList)
        listRouter.start(with: items)
        for _ in 0..<3 { listRouter.advanceNow() }
        let expected = [items[0].url, items[1].url, items[2].url, items[0].url]
        emit("PIC_ROT_LOOPLIST_ORDER=\(listLoader.loaded == expected ? "ok" : "bad")")

        // 3) .shuffle + seed 42：一轮内（去掉首条装载后的 3 次切换）不同 URL 恰 3 个。
        let shuffle = RotationController(scheduler: NoopScheduler(),
                                         random: SeededRandomSource(seed: 42))
        let shuffleLoader = RecordingLoader()
        let shuffleRouter = PlaybackRouter(rotation: shuffle, loader: shuffleLoader)
        shuffle.setMode(.shuffle)
        shuffleRouter.start(with: items)
        for _ in 0..<3 { shuffleRouter.advanceNow() }
        let unique = Set(shuffleLoader.loaded.dropFirst()).count
        emit("PIC_ROT_SHUFFLE_ROUND_UNIQUE=\(unique)")

        // 4) 空列表零装载。
        let empty = RotationController(scheduler: NoopScheduler(),
                                       random: SeededRandomSource(seed: 42))
        let emptyLoader = RecordingLoader()
        let emptyRouter = PlaybackRouter(rotation: empty, loader: emptyLoader)
        emptyRouter.start(with: [])
        emit("PIC_ROT_EMPTY_LOADS=\(emptyLoader.loaded.count)")

        // 5) 设置同步后的当前模式 token（只打 token，不打路径）。
        emit("PIC_ROT_MODE=\(shuffle.mode.rawValue)")

        // 6) 本 driver 打出的行数（含本行与最后一行，共 8 行）。
        emit("PIC_ROT_LINES=8")

        // 7) 应用级启动路径：本 Phase 不采集，登记为 Phase 7 的活（见文件头 ④）。
        emit("PIC_ROT_APP_LAUNCH informational=1 scope=piccore-chain reason=app-launch-blocked-by-locked-screen")
    }
}
