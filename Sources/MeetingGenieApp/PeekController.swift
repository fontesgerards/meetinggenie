import AppKit
import SwiftUI
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

    /// Fired whenever the archive set changes, so the menu's "Re-open" item can
    /// re-validate its enabled state.
    var onArchiveChanged: () -> Void = {}

    init(service: StoreService) {
        self.service = service
        model.onToggle = { [weak self] in self?.toggle(index: $0) }
        model.onDismiss = { [weak self] in self?.dismiss() }
        model.onQuickAddBegin = { [weak self] in self?.beginQuickAdd() }
        model.onQuickAddSubmit = { [weak self] in self?.quickAdd(text: $0) }
    }

    // MARK: - Lifecycle

    /// Show an entry, archiving any currently-shown one first (latest-wins, R11).
    /// An entry with no points is a no-op — the peek stays collapsed (R20).
    func show(_ entry: Entry) {
        guard !entry.points.isEmpty else { return }
        archiveCurrent()
        currentEntryID = entry.id
        model.title = TimeFormatting.display(entry.startTime)
        model.points = entry.points
        model.quickAddVisible = false
        presentPanel()
    }

    /// User dismissed via the close affordance: archive and hide (R14, R23).
    func dismiss() {
        archiveCurrent()
        currentEntryID = nil
        panel?.orderOut(nil)
    }

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
        guard let id = currentEntryID, model.points.indices.contains(index) else { return }
        let newValue = !model.points[index].checked
        try? service.setChecked(entryID: id, index: index, checked: newValue) // R12
        refreshModel(id: id)
    }

    /// Deliberate focus handoff: only now does the non-activating panel take key
    /// status so the text field can accept typing (R25).
    private func beginQuickAdd() {
        panel?.makeKeyAndOrderFront(nil)
    }

    private func quickAdd(text: String) {
        guard let id = currentEntryID else { return }
        // Cap and sanitization are enforced by the service against the fresh
        // store count (R13, R16). A rejected add is a silent no-op for v1.
        try? service.addPoint(entryID: id, text: text)
        refreshModel(id: id)
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

    // MARK: - Panel plumbing

    private func presentPanel() {
        if panel == nil {
            // SwiftUI-in-NSPanel seam (plan review FE1): host the SwiftUI view in
            // an NSHostingView as the panel's content.
            let host = NSHostingView(rootView: PeekView(model: model))
            host.frame = NSRect(x: 0, y: 0, width: 360, height: 140)
            panel = PeekPanel(content: host)
        }
        if let panel, let screen = NSScreen.main {
            panel.setFrame(NotchGeometry.peekFrame(on: screen, size: panel.frame.size), display: true)
        }
        panel?.orderFrontRegardless() // appears without activating the app (R9)
    }
}
