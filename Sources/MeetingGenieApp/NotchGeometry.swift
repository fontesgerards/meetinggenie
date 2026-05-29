import AppKit

/// Notch detection and peek placement (origin R8, R23; plan unit U6).
enum NotchGeometry {
    /// A display is "notched" only when `safeAreaInsets.top > 0`. Plan review
    /// (feasibility) flagged that `auxiliaryTopLeftArea` is non-nil even on
    /// non-notch external displays, so it is NOT a reliable predicate.
    static func hasNotch(_ screen: NSScreen) -> Bool {
        if #available(macOS 12, *) { return screen.safeAreaInsets.top > 0 }
        return false
    }

    /// Frame for the peek: centered horizontally, tucked just under the notch on
    /// a notch display; on a non-notch / external display falls back to a
    /// floating HUD near top-center (origin R8 fallback).
    static func peekFrame(on screen: NSScreen, size: CGSize) -> NSRect {
        let visible = screen.frame
        let x = visible.midX - size.width / 2
        let topInset: CGFloat
        if #available(macOS 12, *) { topInset = screen.safeAreaInsets.top } else { topInset = 0 }
        // On a notch display, sit below the menu-bar/notch band; on a non-notch
        // display, hang a few points down from the top edge.
        let gap = max(topInset, 8) + 4
        let y = visible.maxY - size.height - gap
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
