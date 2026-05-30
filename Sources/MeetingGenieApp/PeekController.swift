import AppKit
import SwiftUI
import QuartzCore
import NotchCore

/// The peek lifecycle state machine (origin R8, R10, R11, R12, R14, R20, R22,
/// R23; AE1–AE4; plan unit U7) plus the interaction wiring to the SwiftUI view
/// (U8).
///
/// All persistence goes through `StoreService` (entry-by-id), which reads the
/// store fresh and mutates one targeted field per call — so check-off and
/// quick-add never clobber a concurrent CLI write with a stale snapshot, and
/// the per-entry cap is enforced against the persisted count. `model.points` is
/// a display cache refreshed from the service after each mutation.
@available(macOS 13, *)
final class PeekController {
    private let service: StoreService
    private let model = PeekModel()
    private var panel: PeekPanel?
    private var currentEntryID: UUID?

    // Browse navigation state (review-navigation feature, U2/U5).
    private var sequence: [ReviewItem] = []
    private var currentIndex: Int?      // position in `sequence` of the shown entry
    private var pendingLive: Entry?     // a meeting that fired while browsing (R11)

    /// Fired whenever the archive set changes, so the menu's "Re-open" item can
    /// re-validate its enabled state.
    var onArchiveChanged: () -> Void = {}

    init(service: StoreService) {
        self.service = service
        model.onToggle = { [weak self] in self?.toggle(index: $0) }
        model.onRemove = { [weak self] in self?.removePoint(index: $0) }
        model.onDismiss = { [weak self] in self?.dismiss() }
        model.onQuickAddBegin = { [weak self] in self?.beginQuickAdd() }
        model.onQuickAddSubmit = { [weak self] in self?.quickAdd(text: $0) }
        model.onPrev = { [weak self] in self?.pagePrev() }
        model.onNext = { [weak self] in self?.pageNext() }
    }

    // MARK: - Lifecycle

    /// Show an entry, archiving any currently-shown one first (latest-wins, R11).
    /// An entry with no points is a no-op — the peek stays collapsed (R20).
    func show(_ entry: Entry) {
        guard !entry.points.isEmpty else { return }
        let wasVisible = panel?.isVisible ?? false
        archiveCurrent()
        currentEntryID = entry.id
        model.title = TimeFormatting.display(entry.startTime)
        model.points = entry.points
        model.quickAddVisible = false
        model.isBrowsing = false
        model.nowBadge = false
        model.emptyMessage = nil
        model.kind = .active
        refreshNavFlags(forEntryID: entry.id) // arrows page off the live peek if neighbors exist
        configurePanel()
        guard let panel else { return }
        // Latest-wins replace (already on screen) swaps content instantly; a
        // fresh appearance slides + fades down from behind the notch (~220ms).
        if wasVisible || Self.reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            let final = panel.frame
            var start = final
            start.origin.y += 8 // begin tucked up behind the notch
            panel.alphaValue = 0
            panel.setFrame(start, display: false)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = Self.mgTiming
                panel.animator().setFrame(final, display: true)
                panel.animator().alphaValue = 1
            }
        }
    }

    /// User dismissed via the close affordance.
    /// While browsing, × exits browse (surfacing a pending-live meeting if one
    /// fired, R12); it never archives the browsed entry. Live dismiss archives
    /// the active entry as before (R14, R23).
    func dismiss() {
        if model.isBrowsing {
            exitBrowse(surfacingPendingLive: true)
            return
        }
        archiveCurrent()
        currentEntryID = nil
        guard let panel, panel.isVisible else { panel?.orderOut(nil); return }
        if Self.reduceMotion {
            panel.orderOut(nil)
            return
        }
        let rest = panel.frame
        var up = rest
        up.origin.y += 8
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = Self.mgTiming
            panel.animator().setFrame(up, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel, weak self] in
            // If a new peek started while this dismiss was animating, leave it
            // alone — don't hide or clobber the freshly-shown panel.
            if self?.currentEntryID != nil { return }
            panel?.orderOut(nil)
            panel?.alphaValue = 1
            panel?.setFrame(rest, display: false) // reset for the next show
        })
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static let mgTiming = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)

    /// Midnight safety net (R10): archive any showing peek and hide.
    func dismissForMidnight() {
        guard currentEntryID != nil else { return }
        dismiss()
    }

    /// Re-open the most recent archived entry from today (R22). Driven by the
    /// menu-bar item — the idle notch stays a strict no-op (R13), which resolves
    /// the R22/R13 conflict raised in plan review.
    func reopenLastArchivedToday() {
        // Pull the previously-dismissed entry before touching the current peek,
        // so we don't re-archive-then-re-pull the same one. show() handles
        // archiving whatever is currently displayed (latest-wins).
        if let entry = try? service.reopenLatestArchivedToday() {
            onArchiveChanged()
            show(entry)
        }
    }

    func hasReopenableEntryToday() -> Bool {
        service.hasReopenableToday()
    }

    // MARK: - Interaction

    private func toggle(index: Int) {
        guard model.kind == .active else { return } // check-off only on the live meeting (R7/R8)
        guard let id = currentEntryID, model.points.indices.contains(index) else { return }
        let newValue = !model.points[index].checked
        try? service.setChecked(entryID: id, index: index, checked: newValue) // R12
        refreshModel(id: id)
    }

    private func removePoint(index: Int) {
        guard model.kind != .past else { return } // past entries are read-only (R7)
        guard let id = currentEntryID, model.points.indices.contains(index) else { return }
        try? service.removePoint(entryID: id, index: index) // R5/R8
        refreshModel(id: id)
        updatePanelFrame()
    }

    /// Deliberate focus handoff: only now does the non-activating panel take key
    /// status so the text field can accept typing (R25).
    private func beginQuickAdd() {
        panel?.makeKeyAndOrderFront(nil)
    }

    private func quickAdd(text: String) {
        guard model.kind != .past else { return } // can't add to history (R7)
        guard let id = currentEntryID else { return }
        // Cap and sanitization are enforced by the service against the fresh
        // store count (R13, R16). A rejected add is a silent no-op for v1.
        try? service.addPoint(entryID: id, text: text)
        refreshModel(id: id)
        updatePanelFrame() // grow the panel so the new point isn't clipped
        panel?.resignKey()
    }

    /// Re-read the entry from the store so the view reflects the persisted
    /// state (including any concurrent CLI changes to the same entry).
    private func refreshModel(id: UUID) {
        if let entry = service.entry(id: id) {
            model.points = entry.points
        }
    }

    /// Archive the currently-shown entry, retaining its checked state. Because
    /// every check-off persists immediately, the stored entry is already
    /// current — archiving moves the persisted entry as-is (R11, R15).
    private func archiveCurrent() {
        guard let id = currentEntryID else { return }
        try? service.archive(entryID: id)
        currentEntryID = nil
        onArchiveChanged()
    }

    // MARK: - Browse navigation (review-navigation U2/U5)

    /// Route a scheduler trigger: while browsing, stash it as pending-live and
    /// raise the "now" badge — never interrupt (R11); otherwise show it live.
    func handleTrigger(_ entry: Entry) {
        if model.isBrowsing {
            pendingLive = entry
            model.nowBadge = true
        } else {
            show(entry)
        }
    }

    /// Open browse at the nearest entry (menu-bar "Review meetings…", U4a).
    func enterBrowse() {
        sequence = service.reviewSequence()
        model.isBrowsing = true
        model.quickAddVisible = false
        if let idx = nearestIndex() {
            currentIndex = idx
            renderCurrent()
        } else {
            currentIndex = nil
            currentEntryID = nil
            model.emptyMessage = "No nearby meetings"
            model.title = ""
            model.points = []
            model.kind = .active
            model.canPrev = false
            model.canNext = false
        }
        presentForBrowse()
    }

    private func nearestIndex() -> Int? {
        if let i = sequence.firstIndex(where: { $0.kind == .active }) { return i }
        if let i = sequence.firstIndex(where: { $0.kind == .upcoming }) { return i }
        return sequence.isEmpty ? nil : sequence.count - 1 // most recent past
    }

    private func pageNext() {
        if model.nowBadge { surfacePendingLive(); return } // › jumps to the live meeting (R12)
        guard let i = currentIndex, i + 1 < sequence.count else { return }
        model.isBrowsing = true
        currentIndex = i + 1
        renderCurrent()
    }

    private func pagePrev() {
        guard let i = currentIndex, i - 1 >= 0 else { return }
        model.isBrowsing = true
        currentIndex = i - 1
        renderCurrent()
    }

    /// Render the item at `currentIndex`. `currentEntryID` targets it for
    /// mutations; the model's `kind` gates which mutations are allowed.
    private func renderCurrent() {
        guard let i = currentIndex, sequence.indices.contains(i) else { return }
        let item = sequence[i]
        currentEntryID = item.entry.id
        model.emptyMessage = nil
        model.title = TimeFormatting.display(item.entry.startTime)
        model.points = item.entry.points
        model.kind = item.kind
        model.quickAddVisible = false
        model.canPrev = i > 0
        model.canNext = i + 1 < sequence.count
        updatePanelFrame()
    }

    /// For the live peek: stash the sequence and set canPrev/canNext so its
    /// arrows can page to neighbors without a separate enter-browse step.
    private func refreshNavFlags(forEntryID id: UUID) {
        sequence = service.reviewSequence()
        if let i = sequence.firstIndex(where: { $0.entry.id == id }) {
            currentIndex = i
            model.canPrev = i > 0
            model.canNext = i + 1 < sequence.count
        } else {
            currentIndex = nil
            model.canPrev = false
            model.canNext = false
        }
    }

    private func exitBrowse(surfacingPendingLive: Bool) {
        let pending = surfacingPendingLive ? pendingLive : nil
        resetBrowseState()
        if let e = pending {
            show(e) // surfaces the live meeting → Active (R12)
        } else {
            orderOutPanel() // → Idle
        }
    }

    private func surfacePendingLive() {
        guard let e = pendingLive else { return }
        resetBrowseState()
        show(e)
    }

    private func resetBrowseState() {
        model.isBrowsing = false
        model.nowBadge = false
        model.emptyMessage = nil
        currentIndex = nil
        sequence = []
        pendingLive = nil
        currentEntryID = nil // so show()'s archiveCurrent / orderOut is a clean no-op
    }

    /// Present the panel for browse: animate in if it wasn't visible, else
    /// update in place. No archive, no live-entrance reset.
    private func presentForBrowse() {
        let wasVisible = panel?.isVisible ?? false
        configurePanel()
        guard let panel else { return }
        if wasVisible || Self.reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            let final = panel.frame
            var start = final
            start.origin.y += 8
            panel.alphaValue = 0
            panel.setFrame(start, display: false)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = Self.mgTiming
                panel.animator().setFrame(final, display: true)
                panel.animator().alphaValue = 1
            }
        }
    }

    /// Animate the panel out to Idle without archiving (browse exit).
    private func orderOutPanel() {
        guard let panel, panel.isVisible else { panel?.orderOut(nil); return }
        if Self.reduceMotion { panel.orderOut(nil); return }
        let rest = panel.frame
        var up = rest
        up.origin.y += 8
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = Self.mgTiming
            panel.animator().setFrame(up, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel, weak self] in
            if self?.currentEntryID != nil || self?.model.isBrowsing == true { return }
            panel?.orderOut(nil)
            panel?.alphaValue = 1
            panel?.setFrame(rest, display: false)
        })
    }

    // MARK: - Panel plumbing

    /// Create (if needed) and size the panel, without ordering it on screen —
    /// `show()` owns the ordering + entrance animation.
    private func configurePanel() {
        let screen = NotchGeometry.targetScreen()
        model.topInset = screen.map(NotchGeometry.notchHeight) ?? 0
        model.notchWidth = screen.map(NotchGeometry.notchWidth) ?? 0
        if panel == nil {
            // SwiftUI-in-NSPanel seam (plan review FE1): host the SwiftUI view in
            // an NSHostingView as the panel's content.
            let host = NSHostingView(rootView: PeekView(model: model))
            // Don't let SwiftUI inset the black fill by the notch/menu-bar safe
            // area — the fill must reach the physical top edge.
            if #available(macOS 13.3, *) { host.safeAreaRegions = [] }
            panel = PeekPanel(content: host)
        }
        updatePanelFrame()
    }

    /// Size the panel flush to the top of the screen, tall enough for the
    /// current point count. Called on present and after quick-add so a new
    /// point is never clipped.
    private func updatePanelFrame() {
        guard let panel, let screen = NotchGeometry.targetScreen() else { return }
        let rows = max(model.points.count, 1)
        let height = model.topInset + CGFloat(rows) * 26 + 76 // notch clearance + rows + chrome
        let size = CGSize(width: PeekView.width, height: height)
        panel.setFrame(NotchGeometry.peekFrame(on: screen, size: size), display: true)
    }
}
