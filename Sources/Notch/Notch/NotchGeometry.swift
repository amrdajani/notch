import AppKit

struct NotchGeometry: Equatable {
    var screen: NSScreen
    var width: CGFloat
    var height: CGFloat
    var hasPhysicalNotch: Bool

    var centerX: CGFloat {
        screen.frame.midX
    }

    var screenFrame: NSRect {
        screen.frame
    }

    static func current() -> NotchGeometry {
        let screen = preferredScreen()
        return measure(screen)
    }

    static func preferredScreen() -> NSScreen {
        if let notched = NSScreen.screens.first(where: hasPhysicalNotch) {
            return notched
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    static func hasPhysicalNotch(_ screen: NSScreen) -> Bool {
        screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil
    }

    static func measure(_ screen: NSScreen) -> NotchGeometry {
        var width: CGFloat = 200
        var height: CGFloat = 32
        let hasNotch = hasPhysicalNotch(screen)

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = screen.frame.width - left.width - right.width
        }
        if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
        }

        return NotchGeometry(
            screen: screen,
            width: width,
            height: height,
            hasPhysicalNotch: hasNotch
        )
    }

    func collapsedFrame(wingExtension: CGFloat) -> NSRect {
        let width = self.width + wingExtension
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    func expandedFrame(size: NSSize, shadowPadding: CGFloat) -> NSRect {
        let width = size.width + shadowPadding * 2
        let height = size.height + shadowPadding
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
