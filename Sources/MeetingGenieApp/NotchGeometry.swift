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

    /// The screen to render the peek on: the built-in notch display when one
    /// exists, else the main screen. `NSScreen.main` follows the active window
    /// and is unreliable for a background agent, which placed the panel on the
    /// wrong screen / below the menu bar.
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: hasNotch) ?? NSScreen.main
    }

    /// True when any connected display has a notch. When false, the peek renders
    /// as the floating fallback below the menu bar (plan unit U1; R1, R2).
    static func anyNotchScreen() -> Bool {
        NSScreen.screens.contains(where: hasNotch)
    }

    /// Height of the notch / menu-bar safe-area band on this screen, used as the
    /// peek's top padding so its first line clears the notch.
    static func notchHeight(_ screen: NSScreen) -> CGFloat {
        if #available(macOS 12, *) { return screen.safeAreaInsets.top }
        return 0
    }

    /// Physical notch width (the empty center gap in the menu bar), derived from
    /// the auxiliary areas that flank it. Returns 0 on a non-notch display.
    static func notchWidth(_ screen: NSScreen) -> CGFloat {
        if #available(macOS 12, *),
           let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width,
           screen.safeAreaInsets.top > 0 {
            return max(0, screen.frame.width - left - right)
        }
        return 0
    }

    /// Frame for the peek: centered horizontally and flush against the very top
    /// of the screen, so a black panel reads as the notch growing downward. The
    /// view supplies its own top padding (= notchHeight) to clear the notch.
    ///
    /// Two seam fixes (researched 2026-05-29): the frame is snapped to physical
    /// pixel boundaries via `backingAlignedRect` (a fractional `frame.maxY` on a
    /// Retina display otherwise rounds the top edge down by one pixel), and the
    /// panel bleeds 1pt above the top edge so the straight top edge has no
    /// hairline gap. `.screenSaver` level already bypasses the menu-bar clamp,
    /// so no `constrainFrameRect` override is needed.
    static func peekFrame(on screen: NSScreen, size: CGSize) -> NSRect {
        let f = screen.frame
        var rect = NSRect(
            x: f.midX - size.width / 2,
            y: f.maxY - size.height, // top edge at the physical top
            width: size.width,
            height: size.height
        )
        rect = screen.backingAlignedRect(
            rect,
            options: [.alignMinXOutward, .alignMaxYOutward, .alignWidthOutward, .alignHeightOutward]
        )
        rect.size.height += 1 // bleed 1pt above the top edge — seamless flush
        return rect
    }

    /// Frame for the floating fallback peek on a non-notch display: centered
    /// horizontally and tucked just below the menu bar, so it reads as a plain
    /// rounded pill rather than something growing out of a notch (plan unit U1;
    /// R1). Pure over `NSRect`/`CGSize` (no `NSScreen`) so it is unit-testable —
    /// the top edge sits at `visibleFrame.maxY` (the bottom of the menu bar),
    /// with no pixel-bleed or flush-top trick.
    static func floatingFrame(screenFrame: NSRect, visibleFrame: NSRect, size: CGSize) -> NSRect {
        NSRect(
            x: screenFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height, // top edge flush under the menu bar
            width: size.width,
            height: size.height
        )
    }

    /// Convenience over `floatingFrame(screenFrame:visibleFrame:size:)` for a
    /// live screen. The caller passes `size.width = PeekView.width` so the
    /// floating pill matches the notch peek's width. The frame is snapped to
    /// physical pixel boundaries (as `peekFrame` does) so a fractional `midX` or
    /// menu-bar height doesn't blur text/borders on a non-Retina external display
    /// — the common non-notch case. No 1pt bleed here: the pill isn't seaming to
    /// a screen edge the way the notch flush-mount is.
    static func floatingFrame(on screen: NSScreen, size: CGSize) -> NSRect {
        let rect = floatingFrame(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, size: size)
        return screen.backingAlignedRect(
            rect,
            options: [.alignMinXOutward, .alignMaxYOutward, .alignWidthOutward, .alignHeightOutward]
        )
    }
}
