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


// 菜单栏模板图必须靠透明间隙成形，实心填充会糊成一块黑矩形。v1 单窗 + 实心三角，v2 双窗 + 实心三角。
func drawMenuBar(_ cg: CGContext, _ px: CGFloat, twoLayer: Bool) {
    let k = px / 1024
    func X(_ v: CGFloat) -> CGFloat { v * k }
    cg.saveGState()
    cg.translateBy(x: 0, y: px); cg.scaleBy(x: 1, y: -1)
    cg.setStrokeColor(CGColor(red:0,green:0,blue:0,alpha:1))
    cg.setFillColor(CGColor(red:0,green:0,blue:0,alpha:1))
    cg.setLineJoin(.round); cg.setLineCap(.round)

    // 整体放大 1.15（绕画布中心）：旧字形只占画布 54.7% 高，20pt 渲染下仅 ~11pt，
    // 在菜单栏里比邻居矮一截。缩放不破坏窗-三角的比例与光学校正（nudge 按比例跟着走）。
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

    let cx: CGFloat = 512
    let cy: CGFloat = twoLayer ? 638 : 512
    let w: CGFloat  = twoLayer ? 232 : 200
    let h: CGFloat  = twoLayer ? 254 : 232
    // 光学校正：nudge = 三角宽 / 6，把面积质心挪到窗心（v1 33 / v2 39）。
    // 三角占窗高比例如上调大（v1 232/560 ≈ 41%），窗内空间校验过放得下。
    let nudge: CGFloat = twoLayer ? 39 : 33
    let tri = CGMutablePath()
    tri.move(to:    CGPoint(x: X(cx - w/2 + nudge), y: X(cy - h/2)))
    tri.addLine(to: CGPoint(x: X(cx + w/2 + nudge), y: X(cy)))
    tri.addLine(to: CGPoint(x: X(cx - w/2 + nudge), y: X(cy + h/2)))
    tri.closeSubpath()
    cg.addPath(tri); cg.fillPath()
    cg.restoreGState()
}

func writeMenuBar(_ px: Int, two: Bool, _ path: String) {
    let c = CGContext(data:nil, width:px, height:px, bitsPerComponent:8, bytesPerRow:0,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.clear(CGRect(x:0,y:0,width:px,height:px))
    drawMenuBar(c, CGFloat(px), twoLayer: two)
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("  \(path)  \(px)×\(px)")
}

print("菜单栏模板图 v1（单窗）:")
writeMenuBar(16, two:false, "\(out)/menubar-v1.png")
writeMenuBar(32, two:false, "\(out)/menubar-v1@2x.png")
writeMenuBar(48, two:false, "\(out)/menubar-v1@3x.png")
print("菜单栏模板图 v2（双窗）:")
writeMenuBar(16, two:true, "\(out)/menubar-v2.png")
writeMenuBar(32, two:true, "\(out)/menubar-v2@2x.png")
writeMenuBar(48, two:true, "\(out)/menubar-v2@3x.png")
