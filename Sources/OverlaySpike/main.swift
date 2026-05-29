import AppKit

// U1 — Feasibility spike (the gate). Throwaway prototype.
//
// Purpose: confirm on the TARGET macOS (26.x here) that a non-activating panel
// at the screen-saver window level renders ABOVE a native-fullscreen call, and
// observe what `sharingType = .none` does / does not exclude from capture.
//
// HOW TO RUN THE GATE (manual — requires a notch Mac + a real call app):
//   1. `swift run overlay-spike`
//   2. Open Zoom/Meet, enter native fullscreen. Confirm the red SPIKE banner
//      stays visible on top.
//   3. Run the capture matrix and note visible/hidden for each:
//        - Zoom "Share entire screen"   (full-display ScreenCaptureKit)
//        - Zoom "Share a window"         (legacy window capture)
//        - macOS built-in screen recording (Cmd-Shift-5)
//        - QuickTime screen recording
//   4. Record results against R8 (above fullscreen) and R24 (best-effort
//      exclusion). Expectation per research: visible locally + above fullscreen;
//      hidden from window-share/legacy; LIKELY visible in full-display SCK share
//      on macOS 15+/26 (the accepted leak).
//   Quit with Ctrl-C.

final class SpikeDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 360
        let height: CGFloat = 44
        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height - 2,
            width: width,
            height: height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // screenSaverWindow (1000) clears native-fullscreen Spaces.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.sharingType = .none // best-effort capture exclusion (R24)

        let label = NSTextField(labelWithString: "● SPIKE: notch overlay above fullscreen — sharingType=.none")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        container.layer?.cornerRadius = 10
        container.addSubview(label)
        panel.contentView = container

        panel.orderFrontRegardless()
        self.panel = panel

        print("overlay-spike running. Level=\(panel.level.rawValue). Enter a fullscreen call and verify the banner stays on top; then run the capture matrix. Ctrl-C to quit.")
    }
}

let app = NSApplication.shared
let delegate = SpikeDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
