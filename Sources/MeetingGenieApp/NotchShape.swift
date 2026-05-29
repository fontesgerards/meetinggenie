import SwiftUI

/// A rounded rectangle whose TOP corners are concave (curving outward into the
/// screen edge) and BOTTOM corners are convex — so a black fill reads as the
/// hardware notch extending downward.
///
/// The concavity comes from quadratic Béziers whose control point sits *at* the
/// corner while the end point is one radius inward, pulling the curve into the
/// rectangle. This is the shape DynamicNotchKit and boring.notch both use
/// (researched 2026-05-29); reproduced here so the app carries no third-party
/// dependency.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left concave corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // Down the left edge to the bottom-left convex corner.
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // Across the bottom edge.
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // Bottom-right convex corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // Up the right edge to the top-right concave corner.
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}

/// A "T" / mushroom shape that is menu-bar-safe: within the menu-bar band
/// (`bandHeight`, == `safeAreaInsets.top`) the painted width is only the
/// physical notch width (centered, in the menu bar's empty notch gap, so it
/// never covers the menu items that flank the notch). Below the band it flares
/// outward through concave shoulders to the full content width, with convex
/// bottom corners. Content lives entirely below the band.
///
/// This is the geometrically-correct overlap fix that the open-source notch
/// apps don't implement (they accept the overlap); researched 2026-05-29.
struct NotchTShape: Shape {
    var notchWidth: CGFloat
    var bandHeight: CGFloat
    var shoulderRadius: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let halfNotch = min(notchWidth, rect.width) / 2
        let l = cx - halfNotch // notch tab left edge
        let r = cx + halfNotch // notch tab right edge
        let bh = min(bandHeight, rect.height)
        var sr = max(0, min(shoulderRadius, bh, halfNotch))
        var br = max(0, min(bottomRadius, rect.height - bh))
        // The shoulder flare and the body corner share the horizontal space on
        // each side of the notch; scale them down proportionally if they'd
        // overlap (wide notch / small screen), which would otherwise self-
        // intersect the path.
        let availableSide = max(0, rect.width / 2 - halfNotch)
        if sr + br > availableSide, sr + br > 0 {
            let scale = availableSide / (sr + br)
            sr *= scale
            br *= scale
        }

        var path = Path()

        // Notch tab top (square — it sits within/over the physical notch).
        path.move(to: CGPoint(x: l, y: rect.minY))
        path.addLine(to: CGPoint(x: r, y: rect.minY))

        // Right tab side down to the right concave shoulder.
        path.addLine(to: CGPoint(x: r, y: bh - sr))
        path.addQuadCurve(to: CGPoint(x: r + sr, y: bh), control: CGPoint(x: r, y: bh))

        // Body top-right edge + convex corner.
        path.addLine(to: CGPoint(x: rect.maxX - br, y: bh))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: bh + br), control: CGPoint(x: rect.maxX, y: bh))

        // Right side + convex bottom-right.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))

        // Bottom edge + convex bottom-left.
        path.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - br), control: CGPoint(x: rect.minX, y: rect.maxY))

        // Left side up + convex body top-left.
        path.addLine(to: CGPoint(x: rect.minX, y: bh + br))
        path.addQuadCurve(to: CGPoint(x: rect.minX + br, y: bh), control: CGPoint(x: rect.minX, y: bh))

        // Body top-left edge to the left concave shoulder, then up the tab side.
        path.addLine(to: CGPoint(x: l - sr, y: bh))
        path.addQuadCurve(to: CGPoint(x: l, y: bh - sr), control: CGPoint(x: l, y: bh))
        path.addLine(to: CGPoint(x: l, y: rect.minY))

        path.closeSubpath()
        return path
    }
}
