import AppKit
import SwiftUI

/// Hosts SwiftUI and takes the first click so fields and buttons work
/// even while the island is a non-activating panel.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {
        if let panel = window as? NotchPanel {
            panel.allowsKey = true
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        super.mouseDown(with: event)
    }
}
