import SwiftUI
import AppKit

@main
struct RenderMain {
    @MainActor
    static func main() {
        let view = SettingsSpike()
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("render failed"); exit(1)
        }
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/spike.png"
        try? png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)  \(png.count) bytes  \(img.size.width)x\(img.size.height)")
    }
}
