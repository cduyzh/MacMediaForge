import AppKit

@main struct MenuBarIconChecks {
    static let phases: [MenuBarState.Phase] = [.idle, .working, .success, .attention]

    /// Render the actual drawing handler into an explicitly sized RGBA bitmap.
    /// Inspect alpha rather than RGB: menu-bar template images use their alpha as a mask.
    static func render(_ image: NSImage, scale: Int) -> NSBitmapImageRep {
        let side = 20 * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: side * 4, bitsPerPixel: 32)!
        bitmap.size = NSSize(width: 20, height: 20)
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    static func alpha(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        // Bitmap rows run top to bottom; geometry in the production image runs bottom to top.
        bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 1 - y)!.alphaComponent
    }

    static func bytes(_ bitmap: NSBitmapImageRep) -> Data {
        Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    static func verifyBadge(_ badge: NSBitmapImageRep, idle: NSBitmapImageRep,
                            scale: Int, phase: MenuBarState.Phase) {
        var solidPixelCount = 0
        var cutoutPixelCount = 0
        var haloPixelCount = 0
        for y in 0..<badge.pixelsHigh {
            for x in 0..<badge.pixelsWide {
                let px = (CGFloat(x) + 0.5) / CGFloat(scale)
                let py = (CGFloat(y) + 0.5) / CGFloat(scale)
                let radius = hypot(px - 16, py - 4)
                let a = alpha(badge, x: x, y: y)
                if radius < 2.8 {
                    if a > 0.9 { solidPixelCount += 1 }
                    if a < 0.5 { cutoutPixelCount += 1 }
                }
                // Where the badge clearance intersects the original ring, the original
                // opaque pixels must be erased instead of being painted white or black.
                if radius > 3.5 && radius < 3.95 && alpha(idle, x: x, y: y) > 0.5 && a < 0.25 {
                    haloPixelCount += 1
                }
            }
        }
        precondition(solidPixelCount >= 5 * scale * scale, "\(phase): badge body must remain opaque")
        precondition(cutoutPixelCount >= scale * scale, "\(phase): badge mark must cut through the alpha mask")
        if scale == 2 {
            precondition(haloPixelCount > 0, "\(phase): badge halo must erase the underlying ring")
        }
    }

    static func makePreview(_ rendered: [[NSBitmapImageRep]], path: String) throws {
        let width = 720, height = 300
        let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: width * 4, bitsPerPixel: 32)!
        let context = NSGraphicsContext(bitmapImageRep: canvas)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .labelColor) {
            (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color
            ])
        }
        label("MediaForge · macOS menu-bar template icons", x: 24, y: 262, size: 17)
        let titles = ["Idle · 准备就绪", "Working · 处理中", "Success · 已完成", "Attention · 需关注"]
        for column in phases.indices {
            let x = CGFloat(24 + column * 174)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 28, width: 150, height: 214), xRadius: 12, yRadius: 12).fill()
            label(titles[column], x: x + 12, y: 214, size: 11)
            for row in 0..<2 {
                let bitmap = rendered[row][column]
                let side = CGFloat(bitmap.pixelsWide)
                let nativeImage = NSImage(size: NSSize(width: side, height: side))
                // Use raster pixel size without interpolation so both scale outputs can be inspected.
                bitmap.size = NSSize(width: side, height: side)
                nativeImage.addRepresentation(bitmap)
                context.imageInterpolation = .none
                let y = CGFloat(row == 0 ? 164 : 79)
                nativeImage.draw(in: NSRect(x: x + (150 - side) / 2, y: y, width: side, height: side))
                label(row == 0 ? "1× · 20 px" : "2× · 40 px", x: x + 43, y: y - 23, size: 10, color: .secondaryLabelColor)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let data = canvas.representation(using: .png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    static func main() throws {
        var rendered: [[NSBitmapImageRep]] = []
        for scale in [1, 2] {
            let bitmaps = phases.map { phase -> NSBitmapImageRep in
                let image = ForgeMenuBarIcon.image(phase: phase)
                precondition(image.isTemplate, "\(phase): icon must follow the system appearance")
                precondition(image.size == NSSize(width: 20, height: 20), "\(phase): expected a 20 × 20 pt icon")
                let bitmap = render(image, scale: scale)
                let values = (0..<bitmap.pixelsHigh).flatMap { y in
                    (0..<bitmap.pixelsWide).map { x in alpha(bitmap, x: x, y: y) }
                }
                precondition(values.contains { $0 > 0.9 } && values.contains { $0 < 0.01 },
                             "\(phase): icon needs both opaque drawing and transparent background")
                return bitmap
            }
            for i in bitmaps.indices {
                for j in bitmaps.indices where j > i {
                    precondition(bytes(bitmaps[i]) != bytes(bitmaps[j]),
                                 "\(phases[i]) and \(phases[j]) must have visibly different pixels at \(scale)×")
                }
            }
            verifyBadge(bitmaps[2], idle: bitmaps[0], scale: scale, phase: .success)
            verifyBadge(bitmaps[3], idle: bitmaps[0], scale: scale, phase: .attention)
            rendered.append(bitmaps)
        }
        if CommandLine.arguments.count > 1 {
            try makePreview(rendered, path: CommandLine.arguments[1])
            print("Preview: \(CommandLine.arguments[1])")
        }
        print("PASS: 四状态 20 × 20 pt 模板图；1×/2× 像素区别、透明背景、徽标镂空与分隔透明环")
    }
}
