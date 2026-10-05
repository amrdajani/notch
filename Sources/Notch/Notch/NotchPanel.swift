import AppKit

/// Borderless overlay that sits under the camera housing.
///
/// Stays on every Space, does not steal focus on hover, and can become
/// key when the user starts typing in chat.
final class NotchPanel: NSPanel {
    var allowsKey = false

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isFloatingPanel = true
        isOpaque = false
        hasShadow = false
        isMovable = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        level = .mainMenu + 3
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            allowsKey = true
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }
}
