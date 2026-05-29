import AppKit

/// The overlay window (origin R8, R9, R24; plan unit U6).
///
/// Recipe validated by the U1 spike / research: a non-activating, borderless
/// panel at the screen-saver window level with `canJoinAllSpaces`,
/// `fullScreenAuxiliary`, and `stationary` renders above native-fullscreen
/// calls. `becomesKeyOnlyIfNeeded` keeps it from stealing focus (R9) until the
/// quick-add path deliberately makes it key (R25). `sharingType = .none` is the
/// best-effort capture exclusion (R24) — note the accepted limitation that
/// full-display ScreenCaptureKit on macOS 15+/26 may still capture it.
final class PeekPanel: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: content.frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        sharingType = .none
        contentView = content
    }

    // Allow the panel to take key status when the quick-add field deliberately
    // requests it (R25). It will not become key on its own (non-activating).
    override var canBecomeKey: Bool { true }

    // Required on macOS 26: AppKit constrains a window so its top can't sit
    // above the menu bar, pushing the peek down by the menu-bar height — even
    // at .screenSaver level. Returning the rect unchanged lets the panel render
    // flush against the physical top edge. (The pixel-snap + 1pt bleed in
    // NotchGeometry.peekFrame remove the residual hairline seam.)
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
