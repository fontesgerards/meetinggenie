import AppKit

/// Idle-notch hover invocation (review-navigation U4b, R9-hover/R10).
///
/// Watches the cursor via a global + local `mouseMoved` monitor (mouse-move
/// monitors need no Accessibility permission, unlike keyboard ones) rather than
/// a sensor window — so it never swallows clicks or steals focus, and a plain
/// click on the idle notch stays a no-op (R10). When the cursor dwells in the
/// notch region it fires `onEnter`; when it leaves the notch ∪ peek region it
/// fires `onExit`. The controller decides what to do (open only when idle;
/// close only if hover-opened and not yet paged).
@available(macOS 13, *)
final class NotchHoverSensor {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    /// The current peek frame (when visible) so moving down from the notch into
    /// the peek doesn't read as leaving.
    var peekFrame: () -> NSRect? = { nil }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var inside = false
    private var dwell: DispatchWorkItem?

    private static let dwellSeconds = 0.25 // brief, so a cursor passing through doesn't open it

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.evaluate()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.evaluate()
            return event
        }
    }

    func stop() {
        [globalMonitor, localMonitor].forEach { if let m = $0 { NSEvent.removeMonitor(m) } }
        globalMonitor = nil
        localMonitor = nil
        dwell?.cancel()
    }

    deinit { stop() }

    /// The notch hit region: the empty notch gap at top-center (notch-width on a
    /// notched display, a modest default otherwise), one band tall.
    private func notchRect() -> NSRect? {
        guard let screen = NotchGeometry.targetScreen() else { return nil }
        let height = max(NotchGeometry.notchHeight(screen), 24)
        let detected = NotchGeometry.notchWidth(screen)
        let width = detected > 1 ? detected : 220
        let frame = screen.frame
        return NSRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }

    private func evaluate() {
        let location = NSEvent.mouseLocation // screen coords, bottom-left origin (matches frames)
        let regions = [notchRect(), peekFrame()].compactMap { $0 }
        let nowInside = regions.contains { $0.contains(location) }

        if nowInside && !inside {
            inside = true
            let work = DispatchWorkItem { [weak self] in
                if self?.inside == true { self?.onEnter() }
            }
            dwell = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwellSeconds, execute: work)
        } else if !nowInside && inside {
            inside = false
            dwell?.cancel()
            onExit()
        }
    }
}
