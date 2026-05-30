import AppKit
import SwiftUI
import QuartzCore
import NotchCore

/// The peek lifecycle + browse navigation (origin notch-meeting-reminders
/// R8–R25, and review-navigation R1–R12).
///
/// `currentEntryID` always names the **live/active** entry — the one that fired
/// and may be archived on dismiss/latest-wins. While browsing, the displayed
/// entry is `sequence[currentIndex]`; mutations target `displayedEntryID()` and
/// are gated by `model.kind`, so browsing never archives or edits the wrong
/// entry. All persistence goes through `StoreService` (entry-by-id) reading the
/// store fresh.
@available(macOS 13, *)
final class PeekController {
    private let service: StoreService
    private let model = PeekModel()
    private var panel: PeekPanel?
    private var currentEntryID: UUID?   // the LIVE/active entry only

    // Browse navigation state (review-navigation U2/U5).
    private var sequence: [ReviewItem] = []
    private var currentIndex: Int?      // position in `sequence` of the shown entry
    private var pendingLive: Entry?     // a meeting that fired while browsing (R11)

    var onArchiveChanged: () -> Void = {}

    init(service: StoreService) {
        self.service = service
        model.onToggle = { [weak self] in self?.toggle(index: $0) }
        model.onRemove = { [weak self] in self?.removePoint(index: $0) }
        model.onEdit = { [weak self] in self?.editPoint(index: $0, text: $1) }
        model.onEditBegin = { [weak self] in self?.beginQuickAdd() } // reuse the key-focus handoff
        model.onDismiss = { [weak self] in self?.dismiss() }
        model.onQuickAddBegin = { [weak self] in self?.beginQuickAdd() }
        model.onQuickAddSubmit = { [weak self] in self?.quickAdd(text: $0) }
        model.onPrev = { [weak self] in self?.pagePrev() }
        model.onNext = { [weak self] in self?.pageNext() }
    }

    // MARK: - Live lifecycle

    /// Show an entry as the live peek, archiving any currently-live one first
    /// (latest-wins, R11). Empty entries are a no-op (R20). Always exits any
    /// browse session.
    func show(_ entry: Entry) {
        guard !entry.points.isEmpty else { return }
        archiveCurrent()           // archives the prior LIVE entry (not a browsed one)
        sequence = []
        currentIndex = nil
        pendingLive = nil
        currentEntryID = entry.id
        model.isBrowsing = false
        model.nowBadge = false
        model.emptyMessage = nil
        model.quickAddVisible = false
        model.kind = .active
        model.title = TimeFormatting.display(entry.startTime)
        model.points = entry.points
        refreshNavFlags(forEntryID: entry.id) // arrows page off the live peek if neighbors exist
        configurePanel()
        presentPanel()
    }

    /// User dismissed via ×. While browsing, exits browse (surfacing a
    /// pending-live meeting if one fired, R12) and archives the live entry it
    /// was opened over; live dismiss archives the active entry (R14, R23).
    func dismiss() {
        if model.isBrowsing {
            exitBrowse(surfacingPendingLive: true)
            return
        }
        archiveCurrent()
        currentEntryID = nil
        guard let panel else { return }
        animateOut(panel) { [weak self] in self?.currentEntryID != nil }
    }

    /// Midnight safety net (R10).
    func dismissForMidnight() {
        guard currentEntryID != nil || model.isBrowsing else { return }
        if model.isBrowsing { exitBrowse(surfacingPendingLive: false); return }
        dismiss()
    }

    /// Re-open the most recent archived entry from today (R22).
    func reopenLastArchivedToday() {
        if let entry = try? service.reopenLatestArchivedToday() {
            onArchiveChanged()
            show(entry) // archives only the live entry; browsed entries are untouched
        }
    }

    func hasReopenableEntryToday() -> Bool {
        service.hasReopenableToday()
    }

    // MARK: - Mutations (gated by recency)

    /// The entry the user is currently looking at — the browsed item while
    /// browsing, else the live entry.
    private func displayedEntryID() -> UUID? {
        if model.isBrowsing, let i = currentIndex, sequence.indices.contains(i) {
            return sequence[i].entry.id
        }
        return currentEntryID
    }

    private func toggle(index: Int) {
        guard model.kind == .active else { return } // check-off only on the live meeting (R7/R8)
        guard let id = displayedEntryID(), model.points.indices.contains(index) else { return }
        let newValue = !model.points[index].checked
        try? service.setChecked(entryID: id, index: index, checked: newValue) // R12
        refreshPoints(id: id)
    }

    private func removePoint(index: Int) {
        guard model.kind != .past else { return } // past entries are read-only (R7)
        guard let id = displayedEntryID(), model.points.indices.contains(index) else { return }
        try? service.removePoint(entryID: id, index: index) // R5/R8
        refreshPoints(id: id)
        updatePanelFrame()
    }

    private func editPoint(index: Int, text: String) {
        guard model.kind != .past else { return } // can't edit history (R7)
        guard let id = displayedEntryID(), model.points.indices.contains(index) else { return }
        try? service.updatePoint(entryID: id, index: index, text: text) // validated/sanitized; empty no-ops
        refreshPoints(id: id)
        updatePanelFrame()
        panel?.resignKey()
    }

    private func beginQuickAdd() {
        panel?.makeKeyAndOrderFront(nil) // deliberate focus handoff (R25)
    }

    private func quickAdd(text: String) {
        guard model.kind != .past else { return } // can't add to history (R7)
        guard let id = displayedEntryID() else { return }
        try? service.addPoint(entryID: id, text: text) // cap + sanitize enforced (R13, R16)
        refreshPoints(id: id)
        updatePanelFrame()
        panel?.resignKey()
    }

    private func refreshPoints(id: UUID) {
        guard let entry = service.entry(id: id) else { return }
        model.points = entry.points
        // Keep the browse cache in sync so paging away and back doesn't show a
        // stale pre-edit copy of this entry.
        if let idx = sequence.firstIndex(where: { $0.entry.id == id }) {
            sequence[idx] = ReviewItem(entry: entry, kind: sequence[idx].kind)
        }
    }

    /// Archive the live entry (retains checked state). No-op if there is none,
    /// or if the id is no longer in the active set (R11, R15).
    private func archiveCurrent() {
        guard let id = currentEntryID else { return }
        try? service.archive(entryID: id)
        currentEntryID = nil
        onArchiveChanged()
    }

    // MARK: - Browse navigation (review-navigation U2/U5)

    /// Route a scheduler trigger: while browsing, stash it and badge it — never
    /// interrupt (R11); otherwise show it live.
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
            model.emptyMessage = "No nearby meetings"
            model.title = ""
            model.points = []
            model.kind = .past // read-only; nothing is mutable in the empty state
            setNavFlags()
        }
        configurePanel()
        presentPanel()
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

    // MARK: - Hover invocation (U4b, R9-hover/R10)

    /// Open browse by notch hover — only when idle (no live peek or browse up).
    /// The peek then stays until the user dismisses it with × (no mouse-away
    /// auto-close). A plain click on the idle notch does nothing (R10): there is
    /// no hover sensor window to receive the click.
    func hoverOpen() {
        guard !(panel?.isVisible ?? false) else { return }
        enterBrowse()
    }

    /// Render the item at `currentIndex`. Does NOT touch `currentEntryID` (that
    /// stays the live entry); mutations resolve the target via displayedEntryID().
    private func renderCurrent() {
        guard let i = currentIndex, sequence.indices.contains(i) else { return }
        let item = sequence[i]
        model.emptyMessage = nil
        model.title = TimeFormatting.display(item.entry.startTime)
        model.points = item.entry.points
        model.kind = item.kind
        model.quickAddVisible = false
        setNavFlags()
        updatePanelFrame()
    }

    /// Stash the sequence + set canPrev/canNext for the live peek so its arrows
    /// page to neighbors without a separate enter-browse step.
    private func refreshNavFlags(forEntryID id: UUID) {
        sequence = service.reviewSequence()
        currentIndex = sequence.firstIndex(where: { $0.entry.id == id })
        setNavFlags()
    }

    private func setNavFlags() {
        let i = currentIndex
        model.canPrev = (i ?? 0) > 0
        model.canNext = i.map { $0 + 1 < sequence.count } ?? false
    }

    private func exitBrowse(surfacingPendingLive: Bool) {
        let pending = surfacingPendingLive ? pendingLive : nil
        if let e = pending {
            resetBrowseState()
            show(e) // archives the prior live entry, then surfaces the live meeting → Active (R12)
        } else {
            archiveCurrent() // archive the live entry browse was opened over (no leak)
            resetBrowseState()
            currentEntryID = nil
            guard let panel else { return }
            animateOut(panel) { [weak self] in
                (self?.currentEntryID != nil) || (self?.model.isBrowsing == true)
            }
        }
    }

    private func surfacePendingLive() {
        guard let e = pendingLive else { model.nowBadge = false; return } // can't strand the badge
        resetBrowseState()
        show(e)
    }

    /// Clear browse-only state. Leaves `currentEntryID` (the live entry) for the
    /// caller to archive or carry into `show()`.
    private func resetBrowseState() {
        model.isBrowsing = false
        model.nowBadge = false
        model.emptyMessage = nil
        currentIndex = nil
        sequence = []
        pendingLive = nil
    }

    // MARK: - Panel plumbing

    /// Create (if needed) and size the panel without ordering it on screen.
    private func configurePanel() {
        let screen = NotchGeometry.targetScreen()
        model.topInset = screen.map(NotchGeometry.notchHeight) ?? 0
        model.notchWidth = screen.map(NotchGeometry.notchWidth) ?? 0
        if panel == nil {
            let host = NSHostingView(rootView: PeekView(model: model)) // SwiftUI-in-NSPanel seam
            if #available(macOS 13.3, *) { host.safeAreaRegions = [] } // reach the physical top edge
            panel = PeekPanel(content: host)
        }
        updatePanelFrame()
    }

    /// Size the panel flush to the top, tall enough for the current point count.
    private func updatePanelFrame() {
        guard let panel, let screen = NotchGeometry.targetScreen() else { return }
        let rows = max(model.points.count, 1)
        let height = model.topInset + CGFloat(rows) * 26 + 76 // notch clearance + rows + chrome
        let size = CGSize(width: PeekView.width, height: height)
        panel.setFrame(NotchGeometry.peekFrame(on: screen, size: size), display: true)
    }

    // MARK: - Motion (calm ease-out; respects Reduce Motion)

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static let mgTiming = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
    private static let duration: CFTimeInterval = 0.22
    private static let slide: CGFloat = 8

    /// Order the panel in, sliding + fading from behind the notch on a fresh
    /// appearance; instant if already visible or Reduce Motion is on.
    private func presentPanel() {
        guard let panel else { return }
        if panel.isVisible || Self.reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        let final = panel.frame
        var start = final
        start.origin.y += Self.slide
        panel.alphaValue = 0
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless() // appears without activating the app (R9)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.duration
            ctx.timingFunction = Self.mgTiming
            panel.animator().setFrame(final, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// Slide + fade the panel out, then hide it — unless `shouldAbort` reports a
    /// new peek took over during the animation.
    private func animateOut(_ panel: PeekPanel, shouldAbort: @escaping () -> Bool) {
        guard panel.isVisible else { panel.orderOut(nil); return }
        if Self.reduceMotion { panel.orderOut(nil); return }
        let rest = panel.frame
        var up = rest
        up.origin.y += Self.slide
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.duration
            ctx.timingFunction = Self.mgTiming
            panel.animator().setFrame(up, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            if shouldAbort() { return }
            panel?.orderOut(nil)
            panel?.alphaValue = 1
            panel?.setFrame(rest, display: false)
        })
    }
}
