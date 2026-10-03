// FullscreenDetectorDriver.swift —— Plan 03-02 T2 的一次性 throwaway 驱动。
//
// 目的：把三件事从「推断」变成「实测」——
//   ① 两个公开 `NSWorkspace` 通知注册成功，打出确切通知名；
//   ② `CGWindowListCopyWindowInfo` 的字典键普查：`tyle` / `ullScreen` 计数为 0
//      ⇒ 公开 API 读不到别的进程的 `styleMask`（D-02 候选 ① 结构上不适用）；
//   ③ 真实全屏跃迁在锁屏会话里观测不到 —— 如实记 `unobservable`，不冒充已验证。
//
// ⚠️ 三条纪律（照 Phase 1 FullscreenProbe 与 03-01 LockWatcherDriver 的写法）：
//   ① **绝不读窗口标题**（T-03-02）。本驱动只用 pid / owner / layer / alpha / bounds。
//      `firstOnscreenWindowDictionaryKeys()` 只取**键名**，不取值 —— 键名本身不含用户数据。
//   ② `FULLSCREEN_TRANSITION=unobservable` 是**事实陈述**：本会话屏幕一直锁着，
//      没有 Space 切换、没有应用激活可等。改成已验证就是伪造。
//   ③ `FULLSCREEN_SIGNAL_ONLY` 是**条件行**：它要求「几何外信号成立但几何不足」，
//      本会话两个信号位恒为 0，跑不出。跑不出就不打 —— 不为了让判据变绿去制造事件。
//
// 编译（scripts/probe-fullscreen.sh 做这件事）：把**产品源码**与本驱动一起编进来，
// 证据跑的是产品代码，不是探针里重写一遍的逻辑：
//   swiftc -parse-as-library -o fullscreendriver \
//     Sources/PicCore/System/FullscreenGeometry.swift \
//     Sources/PicCore/System/FullscreenDetector.swift \
//     .planning/spike/FullscreenDetectorDriver.swift
//
// 本文件不引入播放框架（D-09）。

import Foundation
import AppKit

/// 每行立刻 flush —— 进程可能被 kill，不能靠退出时统一 flush。
func emit(_ line: String) {
    print(line)
    fflush(stdout)
}

func rect(_ r: ScreenRect) -> String {
    String(format: "%.1f,%.1f,%.1f,%.1f", r.x, r.y, r.w, r.h)
}

@main
struct FullscreenDetectorDriver {
    @MainActor
    static func main() {
        // ── ① 注册行：两个公开 NSWorkspace 通知 ─────────────────────────
        emit("FULLSCREEN_SIGNALS_REGISTERED=1 space=\(NSWorkspace.activeSpaceDidChangeNotification.rawValue) activate=\(NSWorkspace.didActivateApplicationNotification.rawValue) deactivate=\(NSWorkspace.didDeactivateApplicationNotification.rawValue)")

        let detector = FullscreenDetector(emit: { emit($0) })
        var lastVerdict: Bool?
        detector.start { fullscreen in
            lastVerdict = fullscreen
        }

        // ── 屏与可见框（D-04 的两个坐标系源）──────────────────────────
        let geom = ScreenGeometry.current()
        emit("SCREEN_FRAME=\(rect(geom?.frame ?? ScreenRect(x: 0, y: 0, w: 0, h: 0)))")
        emit("VISIBLE_FRAME=\(rect(geom?.visible ?? ScreenRect(x: 0, y: 0, w: 0, h: 0)))")
        emit("INSET=14,9,14,9 source=evidence/inset.log")

        // ── 覆盖率与判定 ───────────────────────────────────────────────
        let coverage = detector.currentCoverage() ?? CoverageResult()
        let signals = detector.currentSignals()
        emit(String(format: "COVERAGE=%.3f", coverage.global))
        emit("COVERING=\(signals.covering ? 1 : 0)")
        emit("NON_GEOMETRIC=\(signals.nonGeometricActive ? 1 : 0)")

        // ── 窗口枚举（字段白名单：pid / owner / layer / alpha / bounds）──
        let entries = FullscreenDetector.enumerateWindowEntries()
        for e in entries {
            emit(String(format: "WINDOW pid=%d owner=%@ layer=%d alpha=%.2f bounds=%@",
                        e.pid, e.owner, e.layer, e.alpha, rect(e.raw)))
        }
        emit("WINDOW_COUNT=\(entries.count) layer0_alpha_gt_0")

        // ── ② styleMask 字典键普查（D-02 候选 ① 的实测）───────────────
        let keys = FullscreenDetector.firstOnscreenWindowDictionaryKeys()
        for k in keys {
            emit("WINDOW_DICT_KEY=\(k)")
        }
        if FullscreenDetector.styleMaskKeyPresent(in: keys) {
            emit("STYLEMASK_UNAVAILABLE=0 reason=key_present_in_CGWindowList_dictionary")
        } else {
            emit("STYLEMASK_UNAVAILABLE=1 reason=not_a_key_in_CGWindowList_dictionary")
        }

        // ── ③ 判定行 ───────────────────────────────────────────────────
        let verdict = lastVerdict ?? false
        let reason = verdict
            ? "nonGeometricActive_and_covering"
            : (signals.covering ? "geometry_without_signal" : "not_covering")
        emit("FULLSCREEN_VERDICT=\(verdict ? 1 : 0) reason=\(reason) coverage=\(String(format: "%.3f", coverage.global)) non_geometric=\(signals.nonGeometricActive ? 1 : 0)")

        // ── 真实跃迁：本会话锁屏且无 Space / 应用切换，观测不到 ─────────
        let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? NSNumber
        emit("FULLSCREEN_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=\((locked?.intValue ?? 0) != 0 ? 1 : 0)")

        detector.stop()
        emit("FULLSCREEN_OBSERVERS_REMOVED=\(detector.isRunning ? 0 : 1)")
    }
}