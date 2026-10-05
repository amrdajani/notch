import SwiftUI

/// Island silhouette: tight top corners that hug the hardware cutout,
/// larger bottom corners that bloom into the tray.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let bottom = min(bottomRadius, rect.width / 4, rect.height / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        if top > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                control: CGPoint(x: rect.minX + top, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
        }
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + (top > 0 ? top : 0), y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - (top > 0 ? top : 0), y: rect.maxY)
        )
        if top > 0 {
            path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.maxX - top, y: rect.minY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
