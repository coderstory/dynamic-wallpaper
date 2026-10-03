// MediaLibraryDriver.swift —— Plan 04-01 T3 的一次性 throwaway tracer 驱动。
//
// 目的：一条纵向切片的活体证据 —— 指定文件夹 → MediaLibrary.scan 递归扫出可用
// 视频 → 取第一条 → PlayerController.load(url:) → WallpaperWindowController.attach
// → 窗口 isVisible == true → teardown 后不可见 → 缓存让第二次扫描不再触发遍历。
//
// 两条纪律（照 .planning/spike/LockWatcherDriver.swift 的写法）：
//   ① 每行 print 后立刻 fflush(stdout) —— 进程可能被 kill，不能靠退出时统一 flush。
//   ② **绝不打印任何媒体文件名或完整媒体路径**（T-03-02 隐私纪律）：第 3-7 步
//      全部是计数与布尔量；MEDIA_TRACER_ROOT 是 fixture 树的根路径，不含媒体文件名。
//
// 编译（scripts/probe-media-library.sh 做这件事）：把**产品源码**与本驱动一起编进来，
// 证据跑的是产品代码，不是探针里重写一遍的逻辑。
//
// MEDIA=absent（fixtures/ 未生成）时用 FakeProbe 全收；MEDIA=present 时用产品代码里
// 的 AVFoundationAssetProbe 真读视频轨。fixture 树里的视频文件是真字节（48x48
// Motion-JPEG 种子），两种探针都能走通「第一条进播放器」这条路。

import AppKit
import Foundation

/// 每行立刻 flush —— 进程可能被 kill，不能靠退出时统一 flush。
var tracerLineCount = 0

func emit(_ line: String) {
    print(line)
    fflush(stdout)
    tracerLineCount += 1
}

/// 探针专用假探针：全部接受。只在 MEDIA=absent 时才被选中。
struct FakeProbe: VideoAssetProbe {
    func hasVideoTrack(_ url: URL) async -> Bool { true }
}

@main
struct MediaTracerDriver {
    @MainActor
    static func main() async {
        let args = CommandLine.arguments
        let rootPath = args.count > 1
            ? args[1]
            : (ProcessInfo.processInfo.environment["PIC_TRACER_ROOT"] ?? ".")
        let mediaValue = args.count > 2
            ? args[2]
            : (ProcessInfo.processInfo.environment["PIC_TRACER_MEDIA"] ?? "absent")

        emit("MEDIA_TRACER_ROOT=\(rootPath)")
        emit("MEDIA_TRACER_MEDIA=\(mediaValue)")

        let probe: any VideoAssetProbe = mediaValue == "present"
            ? AVFoundationAssetProbe()
            : FakeProbe()

        let library = MediaLibrary(probe: probe)
        let rootURL = URL(fileURLWithPath: rootPath)

        do {
            let report = try await library.scan(folder: rootURL)

            // 七个过滤计数各占一行（D-17：一个数不能有两种读法）。
            emit("MEDIA_TRACER_SCANNED=\(report.scannedEntryCount)")
            emit("MEDIA_TRACER_EXT_PASS=\(report.acceptedByExtension)")
            emit("MEDIA_TRACER_CONVERTED_SKIPPED=\(report.excludedByConverted)")
            emit("MEDIA_TRACER_CONTAINMENT_SKIPPED=\(report.excludedByContainment)")
            emit("MEDIA_TRACER_PROBE_REJECTED=\(report.rejectedByProbe)")
            emit("MEDIA_TRACER_CAPPED=\(report.skippedByEntryCap ? 1 : 0)")
            emit("MEDIA_TRACER_PLAYABLE=\(report.playableCount)")

            let playerController = PlayerController()
            let wallpaper = WallpaperWindowController()

            if report.items.isEmpty {
                emit("MEDIA_TRACER_PLAN=hidden")
            } else {
                emit("MEDIA_TRACER_PLAN=playing")
                wallpaper.attach(player: playerController.player)
                playerController.load(url: report.items[0].url)
                // AVPlayerLooper 是异步入队的：立即读 items().count 得 0（本机实测），
                // 等 400ms 后读到 3。这是探针构造的 artifact，不是播放缺陷。
                try? await Task.sleep(nanoseconds: 400_000_000)
                emit("MEDIA_TRACER_PLAYER_ITEMS=\(playerController.player.items().count)")
                emit("MEDIA_TRACER_WINDOW_VISIBLE_AFTER_ATTACH=\(wallpaper.window?.isVisible == true ? 1 : 0)")
            }

            // 降级路径的机器前置读数：teardown 后窗口必须不可见（04-03 在这里接 orderOut）。
            wallpaper.teardown()
            emit("MEDIA_TRACER_WINDOW_VISIBLE_AFTER_TEARDOWN=\(wallpaper.window?.isVisible == true ? 1 : 0)")

            // 缓存判据：再扫一次（useCache: true）不应触发第二次遍历。
            _ = try? await library.scan(folder: rootURL, useCache: true)
            emit("MEDIA_TRACER_SCAN_COUNT=\(library.scanCount)")
        } catch {
            emit("MEDIA_TRACER_SCAN_ERROR=\(error)")
            emit("MEDIA_TRACER_PLAN=hidden")
            emit("MEDIA_TRACER_SCAN_COUNT=\(library.scanCount)")
        }

        emit("MEDIA_TRACER_LINES=\(tracerLineCount)")
    }
}