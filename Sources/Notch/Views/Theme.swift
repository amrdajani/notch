import SwiftUI

enum Theme {
    static let accent = Color(red: 0.55, green: 0.82, blue: 0.96)
    static let accentMuted = Color(red: 0.55, green: 0.82, blue: 0.96).opacity(0.16)
    static let surface = Color.black
    static let text = Color.white
    static let muted = Color.white.opacity(0.46)
    static let faint = Color.white.opacity(0.12)
    static let bubbleUser = Color.white.opacity(0.10)
    static let bubbleAssistant = Color(red: 0.55, green: 0.82, blue: 0.96).opacity(0.12)
}

/// Scales and dims a button's label while pressed — the macOS "give" on tap.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Lifts and brightens a card as the pointer enters it.
struct HoverLift: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .brightness(hovering ? 0.05 : 0)
            .scaleEffect(hovering ? 1.012 : 1)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func islandTappable() -> some View {
        contentShape(Rectangle())
    }

    func hoverLift() -> some View { modifier(HoverLift()) }

    func widgetCard() -> some View {
        padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.faint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func glassPanel(radius: CGFloat = 14) -> some View {
        background(Theme.faint, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    func glassCircle() -> some View {
        background(Theme.faint, in: Circle())
    }
}
