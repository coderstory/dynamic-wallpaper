import AppKit
import CoreGraphics

let S: CGFloat = 1024

func roundedRectPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 几何全部按 512 轴对齐：前窗 x=212 w=600 → 212..812 中心512 | 后窗 x=252 w=520 → 252..772 中心512
// 三角 448..576 中心512，y 469..597 居中于前窗 | 基线 300..724 中心512 | 整体 y 250..770 → 中心510
func drawAppIcon(ctx cg: CGContext, px: CGFloat, menuBar: Bool = false) {
    let k = px / S
    func X(_ v: CGFloat) -> CGFloat { v * k }
    let space = CGColorSpaceCreateDeviceRGB()

    if !menuBar {
        // ── 背景（暖白渐变）──
        let bg = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 1.0, green: 0.976, blue: 0.949, alpha: 1),
            CGColor(red: 0.969, green: 0.914, blue: 0.847, alpha: 1)
        ] as CFArray, locations: [0, 1])!
        cg.saveGState()
        cg.addPath(roundedRectPath(CGRect(x:0,y:0,width:px,height:px), X(228)))
        cg.clip()
        cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: px), end: CGPoint(x: px*0.4, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        // ── 橙色光晕（径向）──
        let glow = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 1.0, green: 0.643, blue: 0.239, alpha: 0.42),
            CGColor(red: 1.0, green: 0.643, blue: 0.239, alpha: 0.0)
        ] as CFArray, locations: [0, 1])!
        cg.drawRadialGradient(glow,
            startCenter: CGPoint(x: px*0.5, y: px*0.48), startRadius: 0,
            endCenter:   CGPoint(x: px*0.5, y: px*0.48), endRadius: px*0.5, options: [])
        cg.restoreGState()
    }

    // 坐标系翻转成 SVG 式（y 向下）
    cg.saveGState()
    cg.translateBy(x: 0, y: px)
    cg.scaleBy(x: 1, y: -1)

    let ink: CGColor = menuBar ? CGColor(red:0,green:0,blue:0,alpha:1)
                               : CGColor(red:0.941,green:0.541,blue:0.180,alpha:1)

    // ── 后窗（描边，半透明）──
    cg.setStrokeColor(menuBar ? CGColor(red:0,green:0,blue:0,alpha:0.5) : ink.copy(alpha: 0.42)!)
    cg.setLineWidth(X(30))
    cg.addPath(roundedRectPath(CGRect(x:X(252), y:X(250), width:X(520), height:X(280)), X(52)))
    cg.strokePath()

    // ── 前窗（橙色渐变填充）──
    let winGrad = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1.0,   green: 0.682, blue: 0.302, alpha: 1),
        CGColor(red: 0.910, green: 0.392, blue: 0.102, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    cg.saveGState()
    cg.addPath(roundedRectPath(CGRect(x:X(212), y:X(368), width:X(600), height:X(330)), X(58)))
    cg.clip()
    if menuBar {
        cg.setFillColor(CGColor(red:0,green:0,blue:0,alpha:1))
        cg.fill(CGRect(x:0,y:0,width:px,height:px))
    } else {
        cg.drawLinearGradient(winGrad, start: CGPoint(x:X(212), y:X(698)), end: CGPoint(x:X(632), y:X(368)), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    cg.restoreGState()

    // ── 播放三角（R3 最圆：描边 78 → 圆角半径 39）──
    // 光学校正：实心/描边三角的面积质心天然偏左（≈ 左缘 + 宽/3），等边距下看着偏左。
    // 右移 宽/6 ≈ 21，让质心落到前窗中心 512。
    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: X(448 + 21), y: X(469)))
    tri.addLine(to: CGPoint(x: X(576 + 21), y: X(533)))
    tri.addLine(to: CGPoint(x: X(448 + 21), y: X(597)))
    tri.closeSubpath()
    cg.setLineJoin(.round); cg.setLineCap(.round)
    cg.setFillColor(menuBar ? CGColor(red:0,green:0,blue:0,alpha:1) : CGColor(red:1,green:1,blue:1,alpha:1))
    cg.setStrokeColor(menuBar ? CGColor(red:0,green:0,blue:0,alpha:1) : CGColor(red:1,green:1,blue:1,alpha:1))
    cg.setLineWidth(X(78))
    cg.addPath(tri); cg.fillPath()
    cg.addPath(tri); cg.strokePath()

    // ── 基线 ──
    if !menuBar {
        cg.setStrokeColor(ink.copy(alpha: 0.30)!)
        cg.setLineWidth(X(34)); cg.setLineCap(.round)
        cg.move(to: CGPoint(x:X(300), y:X(770))); cg.addLine(to: CGPoint(x:X(724), y:X(770)))
        cg.strokePath()
    }
    cg.restoreGState()
}

func writePNG(_ px: Int, menuBar: Bool, to path: String) {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x:0,y:0,width:px,height:px))
    ctx.interpolationQuality = .high
    drawAppIcon(ctx: ctx, px: CGFloat(px), menuBar: menuBar)
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("  \(path)  \(px)×\(px)")
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
print("App 图标:")
for (name, px) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),
                   ("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),
                   ("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    writePNG(px, menuBar: false, to: "\(out)/\(name).png")
}


// 菜单栏模板图必须靠透明间隙成形，实心填充会糊成一块黑矩形。
// v3：山形（三座，中间最高）+ 暂停斜线贯穿山体。两态各一套 PNG —— 靠几何区分，
// 不靠 Alpha 灰度：Template 图会被系统按 Alpha 抠成单色，任何灰度都会被拉成锯齿。
func drawMenuBar(_ cg: CGContext, _ px: CGFloat, twoLayer: Bool, paused: Bool) {
    let k = px / 1024
    func X(_ v: CGFloat) -> CGFloat { v * k }
    cg.saveGState()
    cg.translateBy(x: 0, y: px); cg.scaleBy(x: 1, y: -1)
    cg.setStrokeColor(CGColor(red:0,green:0,blue:0,alpha:1))
    cg.setFillColor(CGColor(red:0,green:0,blue:0,alpha:1))
    cg.setLineJoin(.round); cg.setLineCap(.round)

    // 整体放大 1.15（绕画布中心）：字形只占画布约 55% 高，22pt 渲染下仅~11pt，
    // 在菜单栏里比邻居矮一截。缩放不破坏内部比例（各几何量都走 X() 跟着缩）。
    let zoom: CGFloat = 1.15
    cg.translateBy(x: X(512), y: X(512))
    cg.scaleBy(x: zoom, y: zoom)
    cg.translateBy(x: X(-512), y: X(-512))

    if twoLayer {
        cg.setLineWidth(X(63))
        cg.addPath(CGPath(roundedRect: CGRect(x:X(212), y:X(178), width:X(600), height:X(268)),
                          cornerWidth:X(70), cornerHeight:X(70), transform:nil))
        cg.strokePath()
        cg.setLineWidth(X(67))
        cg.addPath(CGPath(roundedRect: CGRect(x:X(180), y:X(398), width:X(664), height:X(456)),
                          cornerWidth:X(78), cornerHeight:X(78), transform:nil))
        cg.strokePath()
    } else {
        cg.setLineWidth(X(76))
        cg.addPath(CGPath(roundedRect: CGRect(x:X(160), y:X(232), width:X(704), height:X(560)),
                          cornerWidth:X(96), cornerHeight:X(96), transform:nil))
        cg.strokePath()
    }

    // ── 三座山（v3 替换 v1/v2 的播放三角）──
    // 中间最高最宽（270），两侧矮而窄（230）。高度差 40 在 22pt 下约 0.9pt ——
    // 是「看得出主次但不会读成两座独立山」的量；再大就散成三个孤立三角。
    //
    // **基线 646 是算出来的，不是抄来的**：窗 v1 是 y 232..792，几何中心 512。
    // 山此前取基线 700 → 外接框 428..700、几何中心 564，**偏下 52px**
    // （1024 画布换算到 22pt 就是 1.1pt，肉眼可辨「吊在下面」）。
    // 修正目标取「外接框中心略高于窗心」而非严格等于：三角形的**视觉重心**在面积
    // 质心（离底边 h/3），比外接框中心低 h/6 ≈ 45px。若让质心精确落在窗心，
    // 外接框得再上移 45px，看起来又会「浮在上面」。取 646 让外接框中心落在 510
    // （比窗心高 2px）—— 折中后的读感是「稳在中间」。
    let baseY: CGFloat = twoLayer ? 688 : 646
    // 三山 366/512/658 均衡分布（不是刻意聚在中间）。侧山压到 200、中山抬到 300 ——
    // 高度差100 画布 px 在 22pt 下约 2.2pt，是「一眼看出中间最高」又「三座仍读作三座」的量。
    // 更早版本侧山曾压到 166 并外移到 322/702：那是为了躲斜线，结果山挤成一坨、
    // 分布感全失。**改斜率（见下）比挪山位更优** —— 不动造型也能让线避开峰顶。
    let peaks: [(x: CGFloat, w: CGFloat, h: CGFloat)] = [
        (366, 150, 200),   // 左山：矮
        (512, 270, 300),   // 中山：最高、宽
        (658, 150, 200),   // 右山：矮
    ]
    for pk in peaks {
        let m = CGMutablePath()
        m.move(to: CGPoint(x: X(pk.x - pk.w / 2), y: X(baseY)))
        m.addLine(to: CGPoint(x: X(pk.x), y: X(baseY - pk.h)))
        m.addLine(to: CGPoint(x: X(pk.x + pk.w / 2), y: X(baseY)))
        m.closeSubpath()
        cg.addPath(m); cg.fillPath()
    }

    // ── 暂停斜线：左上贯穿到右下，压过山体 ──
    // 线宽 62 ≈ 中山宽 244 的 25%。先试了 96 —— 那太粗：22pt 下斜线两侧各压掉一整座山，
    // 三座山糊成一团黑，只剩「一个斜杠」的读法，反而丢了山本身。
    // 两端各外伸出山外 —— 只在山体内画一段会被读成「山上的纹路」，不是「暂停」。
    // 斜率刻意压平：dy/dx ≈ 0.51，即约 27°。 steeper 的试过（0.83 / 45°），
    // 斜线会与右山山脊重合、把右山劈成两半；平缓些它就只是「横穿三座山的一道线」。
    // 两端只探出山体一小截，不是穿出画布：伸太长时右上端会翘出一块盖住右山峰的
    // 「角」，山形就废了 —— 斜线的作用是「横穿」，不是「划破」。
    //
    // y 值随山基线一起上移 54（752→698）：斜线必须跟着山走，不能自己留在旧位置。
    // 旧版本中点落在 y=629（偏下 117px），比山重心还低 70px，看着像另画的一笔。
    // 现在中点 575，与山质心 555 同量级，视觉上仍读作「压在山上」。
    //
    // **斜线是解出来的，不是画出来的**（用户：「斜线不完整，应该是贯穿对角线」）。
    // 旧值 (320,692)→(680,470) 的两端都在山体内部（山体 x 271..753），
    // 所以画出来只是山腰上的一小段，横看竖看都不成「线」。
    //
    // 目标：两端**穿出窗框**（窗 x 160..864，各超出 30）、中途**穿过全部三座山**。
    // 斜率 k = **0.38**（21°），不是随手取的 —— 它是「每座山的切入深度」权衡出来的：
    //   k=0.30 → 中山只切 33%，但线太平，读起来像「横线」不像「斜线」；
    //   k=0.46 → 线够斜，但三山各被切 40~50%，山形糊掉（试过，见下方「切入」注释）。
    // 0.38 是这个区间里三山形体保留最好的点：切入中山 36% / 右山 32% /
    // **左山 -23%（线在其峰顶之上，完全不被劈）**。左山豁免是因为线自左下向右上、
    // 左山恰好落在线的下方空白区 —— 这是 k 的选取要让「三山同时成立」的真正原因。
    //
    // 锚点：令线在右山 (x=658) 处 y=400（峰顶 446 之下 46px），反解直线方程。
    // 校验三峰处线y = 561 / 497 / 400，均在各自峰顶与基线 646 之间 → 确实穿山。
    //
    // 线宽 50：中山宽 270 的 19%。96 那版太粗，两侧山被压掉、糊成一团黑。
    if paused {
        cg.setLineWidth(X(50))
        cg.move(to: CGPoint(x: X(130), y: X(601)))
        cg.addLine(to: CGPoint(x: X(894), y: X(310)))
        cg.strokePath()
    }
    cg.restoreGState()
}

func writeMenuBar(_ px: Int, two: Bool, paused: Bool, _ path: String) {
    let c = CGContext(data:nil, width:px, height:px, bitsPerComponent:8, bytesPerRow:0,
                      space:CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.clear(CGRect(x:0,y:0,width:px,height:px))
    drawMenuBar(c, CGFloat(px), twoLayer: two, paused: paused)
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("  \(path)  \(px)×\(px)")
}

// 只出 v1（单窗）+ 两态。v2（双窗）曾存在但没有任何消费方 —— AppDelegate 只读v1，
// build.sh 也只拷 v1；留着它就是「看起来还有第二套设计」的死资源，删掉。
// 需要双窗版时把 twoLayer 传 true 即可，函数本身还支持。
for (paused, suffix) in [(false, ""), (true, "-paused")] {
    print("菜单栏模板图 v1\(paused ? " 暂停" : "")：")
    writeMenuBar(16, two: false, paused: paused, "\(out)/menubar-v1\(suffix).png")
    writeMenuBar(32, two: false, paused: paused, "\(out)/menubar-v1\(suffix)@2x.png")
    writeMenuBar(48, two: false, paused: paused, "\(out)/menubar-v1\(suffix)@3x.png")
}
