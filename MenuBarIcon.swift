import AppKit

/// A template drawing stays sharp at menu-bar size and follows the system appearance.
enum ForgeMenuBarIcon {
    static func image(phase: MenuBarState.Phase) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let ring = NSBezierPath()
            ring.appendArc(withCenter: NSPoint(x: 9, y: 10), radius: 7.2,
                           startAngle: phase == .working ? 45 : 10, endAngle: phase == .working ? 315 : 350)
            ring.lineWidth = 1.6
            ring.lineCapStyle = .round
            ring.stroke()
            let play = NSBezierPath()
            play.move(to: NSPoint(x: 7, y: 6.5))
            play.line(to: NSPoint(x: 12, y: 10))
            play.line(to: NSPoint(x: 7, y: 13.5))
            play.close()
            play.fill()
            if phase == .success || phase == .attention {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSBezierPath(ovalIn: NSRect(x: 12, y: 0, width: 8, height: 8)).fill()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12.6, y: 0.6, width: 6.8, height: 6.8)).fill()
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSColor.black.setStroke()
                let mark = NSBezierPath()
                mark.lineWidth = 1
                mark.lineCapStyle = .round
                if phase == .success {
                    mark.move(to: NSPoint(x: 14, y: 4)); mark.line(to: NSPoint(x: 15.4, y: 2.6)); mark.line(to: NSPoint(x: 18, y: 5.2))
                } else {
                    mark.move(to: NSPoint(x: 16, y: 5.6)); mark.line(to: NSPoint(x: 16, y: 3.7))
                    mark.move(to: NSPoint(x: 16, y: 2.5)); mark.line(to: NSPoint(x: 16, y: 2.4))
                }
                mark.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

