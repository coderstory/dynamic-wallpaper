// FullscreenProbe.swift —— Phase 01 门禁 spike 03（PLAN 01-03 Task 1），一次性 throwaway 全屏几何探针。
//
// 回答的问题：当前这台机器的桌面上，有没有某个应用的窗口把 visibleFrame 铺满了
// （PITFALLS.md Pitfall 2 的几何判定原型）。纯 CLI，跑完即退，无 GUI 常驻。
//
// 坐标系陷阱（01-CONTEXT <planner_partial_findings>，明确标注「未完成验证，待复核」）：
// CGWindowListCopyWindowInfo 报的 bounds 是左上角原点；NSScreen.frame / visibleFrame 是
// 左下角原点。本探针 **不引用** planner 的中途观察，自己跑一行 COORD= 判定 confirmed /
// unconfirmed —— 要么确认、要么推翻它。
//
// 另一个独立偏差（plan 01-01 门禁实测）：任何 -2147483623 层的 borderless 窗口，
// CGWindowList 报 14,9,1442,938，比 NSScreen.frame 系统性内缩 14pt(宽) / 9pt(高)，四边对称。
// 与 33pt 刘海内缩叠加共 47pt。本探针不补偿它（它只在桌面层窗口上出现，与 layer-0 判定无关），
// 但覆盖率分母统一用 visibleFrame，不用屏幕 bounds。
//
// 核心算法（不可替换）：按 kCGWindowOwnerPID 聚合后再算覆盖率。逐窗口取最大在 Chrome 同 pid
// 双窗口（bounds=0,33,1470,124 + bounds=0,121,1470,835）上必漏判 —— PITFALLS 实测 87.343%。
// 聚合口径打出来的 per_window_best 只是为了让「聚合到底带来了多少」可见，不是目标值。
//
// 隐私：输出只含 owner / layer / pid / alpha / bounds / coverage。窗口标题字段可能含用户
// 文件路径（T-01-06），本文件全篇不引用该常量，验收以 grep 计数为 0 把关。
//
// 编译：swiftc -parse-as-library -target arm64-apple-macosx15.0 \
//       -o .planning/spike/out/fullscreenprobe .planning/spike/FullscreenProbe.swift

import AppKit
import CoreGraphics

// MARK: - 几何

/// 矩形。`topLeftOrigin` 记录数值来自哪种坐标系，避免把两种原点的 y 直接相减。
struct Box {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    var area: Double { max(0, w) * max(0, h) }
    var text: String { "\(fmt(x)),\(fmt(y)),\(fmt(w)),\(fmt(h))" }
}

/// 一扇 eligible 窗口。`raw` 是 CGWindowList 原样报的值（左上角原点）。
struct Win {
    let pid: Int
    let owner: String
    let layer: Int
    let alpha: Double
    let raw: Box
}

/// 左上角原点 → 左下角原点。方向固定（威胁 T-01-14：写反会让 coverage 恒为 0）。
func flipTopLeftToBottomLeft(_ b: Box, screenH: Double) -> Box {
    Box(x: b.x, y: screenH - (b.y + b.h), w: b.w, h: b.h)
}

func intersect(_ a: Box, _ b: Box) -> Box {
    let x1 = max(a.x, b.x)
    let y1 = max(a.y, b.y)
    let x2 = min(a.x + a.w, b.x + b.w)
    let y2 = min(a.y + a.h, b.y + b.h)
    return Box(x: x1, y: y1, w: x2 - x1, h: y2 - y1)
}

func fmt(_ v: Double) -> String { String(v.rounded()) }
func pct(_ v: Double) -> String { String(format: "%.3f", v) }

/// 覆盖率聚合结果。
struct Coverage {
    var global: Double = 0
    var globalPid: Int = -1
    var rectCount: Int = 0
    /// **被本计划明确否决的朴素口径**：同一个 pid 下，每个 rect 单独算覆盖率的最大值。
    var perWindowBest: Double = 0
}

/// 按 pid 聚合：组内每个 rect 先翻转到左下角原点，再各自与 visibleFrame 求交面积，
/// **求和**后除以 visibleFrame 面积并封顶 1.0。不同 pid 之间取最大值作为全局 coverage。
func aggregate(_ wins: [Win], visible: Box, screenH: Double) -> Coverage {
    var groups: [Int: [Win]] = [:]
    for w in wins { groups[w.pid, default: []].append(w) }

    let vArea = visible.area
    var out = Coverage()

    for pid in groups.keys.sorted() {
        let ws = groups[pid]!
        var sum = 0.0
        var best = 0.0
        for w in ws {
            let a = intersect(flipTopLeftToBottomLeft(w.raw, screenH: screenH), visible).area
            sum += a
            best = max(best, a / vArea)
        }
        let cov = vArea > 0 ? min(1.0, sum / vArea) : 0
        if cov > out.global {
            out.global = cov
            out.globalPid = pid
            out.rectCount = ws.count
            out.perWindowBest = best
        }
    }
    return out
}

// MARK: - 环境

struct Env {
    let screen: Box          // frame，左下角原点
    let visible: Box         // visibleFrame（刘海内缩后），左下角原点
    let scale: Double
}

func readEnv() -> Env? {
    guard let s = NSScreen.main else { return nil }
    let f = s.frame, v = s.visibleFrame
    return Env(screen: Box(x: Double(f.origin.x), y: Double(f.origin.y), w: Double(f.width), h: Double(f.height)),
               visible: Box(x: Double(v.origin.x), y: Double(v.origin.y), w: Double(v.width), h: Double(v.height)),
               scale: Double(s.backingScaleFactor))
}

/// 枚举 layer-0、有 alpha、非本进程的窗口。kCGWindowAlpha 过滤掉透明/未绘制的占位窗。
func enumerateWindows(onlyPid: Int?) -> [Win] {
    let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    // 自排除按 **PID**，不按 owner 名：S1 里被测窗口恰好来自同一个可执行文件（fullscreenprobe），
    // 按名字排除会把它一起滤掉（实测 rects=0）。编排器硬性指令也是「一律按 PID 认领」。
    let me = ProcessInfo.processInfo.processIdentifier
    var out: [Win] = []
    for e in raw {
        guard let layerNum = e[kCGWindowLayer as String] as? NSNumber,
              let pidNum = e[kCGWindowOwnerPID as String] as? NSNumber else { continue }
        let layer = layerNum.intValue
        guard layer == 0 else { continue }
        let alpha = (e[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0
        guard alpha > 0 else { continue }
        let owner = e[kCGWindowOwnerName as String] as? String ?? "?"
        let pid = pidNum.intValue
        guard pid != me else { continue }
        if let only = onlyPid, pid != only { continue }
        var b = Box(x: 0, y: 0, w: 0, h: 0)
        if let r = e[kCGWindowBounds as String] as? [String: Any],
           let x = (r["X"] as? NSNumber)?.doubleValue, let y = (r["Y"] as? NSNumber)?.doubleValue,
           let w = (r["Width"] as? NSNumber)?.doubleValue, let h = (r["Height"] as? NSNumber)?.doubleValue {
            b = Box(x: x, y: y, w: w, h: h)
        }
        out.append(Win(pid: pid, owner: owner, layer: layer, alpha: alpha, raw: b))
    }
    out.sort { a, b2 in a.pid != b2.pid ? a.pid < b2.pid : a.owner < b2.owner }
    return out
}

// MARK: - 入口

@main
struct FullscreenProbeMain {
    static let threshold = 0.95

    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let env = readEnv() else {
            print("ERROR=no_main_screen"); exit(2)
        }

        if args.isEmpty {
            printUsage(); exit(2)
        }
        switch args[0] {
        case "--inspect":        inspect(env, Array(args.dropFirst()))
        case "--replay":         replay(env, Array(args.dropFirst()))
        case "--selftest":       selftest(env)
        case "--spawn-fullscreen": spawnFullscreen(env)
        default:
            print("ERROR=unknown_subcommand argv0=\(args[0])"); printUsage(); exit(2)
        }
    }

    static func printUsage() {
        print("USAGE=fullscreenprobe --inspect <name> [--pid <n>]")
        print("USAGE=fullscreenprobe --replay <name> <w> <h> <pid> <x> <y> <w> <h> [...]")
        print("USAGE=fullscreenprobe --selftest")
        print("USAGE=fullscreenprobe --spawn-fullscreen")
    }

    /// 会话锁屏状态。锁屏时 CGWindowList 报出的几何仍然真实，但它不代表「桌面当前可见」。
    /// 覆盖率数字不带这个上下文就会误导，所以每条 inspect / replay 都打一行 LOCK=。
    static func lockState() -> String {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any],
              let v = dict["CGSSessionScreenIsLocked"] as? NSNumber else { return "unknown" }
        return v.boolValue ? "1" : "0"
    }

    static func header(_ env: Env) {
        print("SCREEN frame=\(env.screen.text) visible=\(env.visible.text) scale=\(fmt(env.scale))")
        print("LOCK=\(lockState()) source=CGSessionCopyCurrentDictionary.CGSSessionScreenIsLocked")
    }

    // MARK: --inspect

    static func inspect(_ env: Env, _ rest: [String]) {
        let name = rest.first ?? "unnamed"
        var onlyPid: Int? = nil
        var i = 1
        while i < rest.count {
            if rest[i] == "--pid", i + 1 < rest.count, let p = Int(rest[i + 1]) { onlyPid = p; i += 2 } else { i += 1 }
        }

        header(env)
        print("THRESHOLD=\(pct(threshold))")
        print("DENOMINATOR=visibleFrame visible_area=\(fmt(env.visible.area))")

        let wins = enumerateWindows(onlyPid: onlyPid)

        // 坐标系自证：对每个 eligible 窗口同时打两种 y。
        var coordHits = 0
        for w in wins {
            let flipped = flipTopLeftToBottomLeft(w.raw, screenH: env.screen.h)
            let inYRange = flipped.y >= env.visible.y - 1 && flipped.y <= (env.visible.y + env.visible.h) + 1
            if inYRange { coordHits += 1 }
            print("WIN pid=\(w.pid) owner=\(w.owner) layer=\(w.layer) alpha=\(String(format: "%.2f", w.alpha)) " +
                  "bounds=\(w.raw.text) flipped_y=\(pct(flipped.y)) flipped_in_visible_y=\(inYRange ? 1 : 0)")
        }
        print("COORD=\(coordHits > 0 ? "confirmed" : "unconfirmed") COORD_MATCHED_WINDOWS=\(coordHits) COORD_WINDOWS=\(wins.count)")

        let cov = aggregate(wins, visible: env.visible, screenH: env.screen.h)
        if let only = onlyPid {
            print("TOP_PID=\(only) coverage=\(pct(cov.global)) rects=\(cov.rectCount)")
        } else {
            print("TOP_PID=\(cov.globalPid) coverage=\(pct(cov.global)) rects=\(cov.rectCount)")
        }
        print("COVERAGE_PER_WINDOW_BEST=\(pct(cov.perWindowBest)) method=per_pid_aggregate_naive_alt=per_window_max")
        let fs = cov.global >= threshold
        print("SCENARIO=\(name) source=live coverage=\(pct(cov.global)) fullscreen=\(fs) pid=\(cov.globalPid) rects=\(cov.rectCount)")
    }

    // MARK: --replay

    static func replay(_ env: Env, _ rest: [String]) {
        // --replay <name> <targetW> <targetH> <pid> <x> <y> <w> <h> [<x> <y> <w> <h> ...]
        // rest = [name, targetW, targetH, pid] + 每 rect 4 个数 → 总长必须是 4 的倍数且 >= 8。
        guard rest.count >= 8, rest.count % 4 == 0 else {
            print("ERROR=replay_arg_shape argc=\(rest.count)"); exit(2)
        }
        let name = rest[0]
        let tw = Double(rest[1]) ?? 0, th = Double(rest[2]) ?? 0
        let pid = Int(rest[3]) ?? -1

        header(env)
        var wins: [Win] = []
        var k = 4
        while k + 3 < rest.count {
            let x = Double(rest[k]) ?? 0, y = Double(rest[k + 1]) ?? 0
            let w = Double(rest[k + 2]) ?? 0, h = Double(rest[k + 3]) ?? 0
            wins.append(Win(pid: pid, owner: name, layer: 0, alpha: 1, raw: Box(x: x, y: y, w: w, h: h)))
            print("REPLAY_RECT pid=\(pid) bounds=\(Box(x: x, y: y, w: w, h: h).text)")
            k += 4
        }
        print("TARGET=\(fmt(tw))x\(fmt(th))")
        let cov = aggregate(wins, visible: env.visible, screenH: env.screen.h)
        print("TOP_PID=\(cov.globalPid) coverage=\(pct(cov.global)) rects=\(cov.rectCount)")
        print("COVERAGE_PER_WINDOW_BEST=\(pct(cov.perWindowBest)) method=per_pid_aggregate_naive_alt=per_window_max")
        let fs = cov.global >= threshold
        print("SCENARIO=\(name) source=synthetic coverage=\(pct(cov.global)) fullscreen=\(fs) pid=\(cov.globalPid) rects=\(cov.rectCount)")
    }

    // MARK: --selftest

    static func selftest(_ env: Env) {
        header(env)
        print("THRESHOLD=\(pct(threshold))")
        print("SELFTEST_DENOMINATOR=visibleFrame")

        // 三条内置几何，rect 一律按 CGWindowList 左上角原点原样传入。
        let cases: [(String, [(Double, Double, Double, Double)])] = [
            ("whole",  [(0, 33, 1470, 833)]),
            ("chrome", [(0, 33, 1470, 124), (0, 121, 1470, 835)]),
            ("split",  [(0, 33, 1470, 500), (0, 533, 1470, 400)]),
        ]
        var failures = 0
        for (name, rects) in cases {
            let wins = rects.map { Win(pid: 1000, owner: name, layer: 0, alpha: 1,
                                      raw: Box(x: $0.0, y: $0.1, w: $0.2, h: $0.3)) }
            for w in wins { print("SELFTEST_RECT \(name) bounds=\(w.raw.text)") }
            let cov = aggregate(wins, visible: env.visible, screenH: env.screen.h)
            print("SELFTEST=\(name) coverage=\(pct(cov.global)) per_window_best=\(pct(cov.perWindowBest))")
            if abs(cov.global - 1.0) > 0.005 { failures += 1 }
        }
        // split 是唯一能区分「按 pid 聚合」与「逐窗口取最大」的用例：
        // 两块各 0.600 / 0.400，合起来才 1.000。若实现退化成逐窗口取最大，本行会变 0.600。
        let splitBest: Double = {
            let rects = cases.first { $0.0 == "split" }!.1
            let wins = rects.map { Win(pid: 1000, owner: "split", layer: 0, alpha: 1,
                                      raw: Box(x: $0.0, y: $0.1, w: $0.2, h: $0.3)) }
            return aggregate(wins, visible: env.visible, screenH: env.screen.h).perWindowBest
        }()
        print("SELFTEST_SPLIT_EXPECT_PER_WINDOW_BEST=0.600 actual=\(pct(splitBest))")
        if abs(splitBest - 0.600) > 0.005 { failures += 1 }
        print("SELFTEST_FAILURES=\(failures)")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: --spawn-fullscreen

    @MainActor
    static func spawnFullscreen(_ env: Env) {
        // T-01-07：抢用户屏幕前先在 stderr 明示，并给硬性 10 秒上限。
        FileHandle.standardError.write("WARN=fullscreen_for_5s\n".data(using: .utf8)!)

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let win = NSWindow(contentRect: NSRect(x: env.screen.x, y: env.screen.y, width: env.screen.w, height: env.screen.h),
                           styleMask: [.fullSizeContentView],
                           backing: .buffered,
                           defer: false)
        win.title = "FullscreenProbe"
        win.level = .normal            // 不设 collectionBehavior → 正常 app 窗口
        win.backgroundColor = .magenta
        win.makeKeyAndOrderFront(nil)
        win.toggleFullScreen(nil)

        print("SPAWN_FULLSCREEN=pid=\(ProcessInfo.processInfo.processIdentifier)")
        print("SPAWN_SCREEN=\(env.screen.text) visible=\(env.visible.text)")
        fflush(stdout)

        // 观测 toggleFullScreen 是否真的生效（锁屏状态下可能不生效 —— 这正是要测的）。
        var sawFullScreen = false
        var elapsed = 0.0
        while elapsed < 10.0 {
            if win.styleMask.contains(.fullScreen) { sawFullScreen = true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.25))
            elapsed += 0.25
        }
        print("FINAL_FULLSCREEN=\(win.styleMask.contains(.fullScreen) ? 1 : 0)")
        print("MAX_OBSERVED_FULLSCREEN=\(sawFullScreen ? 1 : 0)")
        print("SPAWN_EXIT=ok reason=timeout_10s")
        fflush(stdout)

        win.toggleFullScreen(nil)
        exit(0)
    }
}
