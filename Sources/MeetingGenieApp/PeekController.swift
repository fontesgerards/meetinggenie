import AppKit
import SwiftUI
import NotchCore

/// The peek lifecycle state machine (origin R8, R10, R11, R12, R14, R20, R22,
/// R23; AE1–AE4; plan unit U7) plus the interaction wiring to the SwiftUI view
/// (U8). Archive transitions are app-orchestration over the NotchCore store.
@available(macOS 13, *)
final class PeekController {
    private let store: Store
    private let model = PeekModel()
    private var panel: PeekPanel?
    private var currentEntryID: UUID?

    /// Fired whenever the archive set changes, so the menu's "Re-open" item can
    /// re-validate its enabled state.
    var onArchiveChanged: () -> Void = {}

    init(store: Store) {
        self.store = store
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
        model.title = Self.timeString(entry.startTime)
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

    /// Midnight safety net (R10): any showing peek is archived and hidden.
    func dismissForMidnight() {
        guard currentEntryID != nil else { return }
        dismiss()
    }

    /// Re-open the most recent archived entry from today (R22). Driven by the
    /// menu-bar item — the idle notch itself stays a strict no-op (R13), which
    /// resolves the R22/R13 conflict raised in plan review.
    func reopenLastArchivedToday(now: Date = Date(), calendar: Calendar = .current) {
        guard var data = try? store.load() else { return }
        let todays = data.archive.filter { calendar.isDate($0.startTime, inSameDayAs: now) }
        guard let entry = todays.max(by: { $0.startTime < $1.startTime }) else { return }
        data.archive.removeAll { $0.id == entry.id }
        data.entries.append(entry) // becomes live again
        try? store.save(data)
        onArchiveChanged()
        show(entry)
    }

    func hasReopenableEntryToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let data = try? store.load() else { return false }
        return data.archive.contains { calendar.isDate($0.startTime, inSameDayAs: now) }
    }

    // MARK: - Interaction

    private func toggle(index: Int) {
        guard model.points.indices.contains(index) else { return }
        model.points[index].checked.toggle() // R12
        persistCurrentPoints()
    }

    /// Deliberate focus handoff: only now does the non-activating panel take key
    /// status so the text field can accept typing (R25).
    private func beginQuickAdd() {
        panel?.makeKeyAndOrderFront(nil)
    }

    private func quickAdd(text: String) {
        let clean = (try? Validation.validatePoint(text)) ?? ""
        guard !clean.isEmpty, model.points.count < Limits.maxPointsPerEntry else { return }
        model.points.append(Point(text: clean)) // R13, R16
        persistCurrentPoints()
        // Return key focus to the previously active app.
        panel?.resignKey()
        NSApp.deactivate()
    }

    // MARK: - Persistence

    private func persistCurrentPoints() {
        guard let id = currentEntryID, var data = try? store.load() else { return }
        if let idx = data.entries.firstIndex(where: { $0.id == id }) {
            data.entries[idx].points = model.points
            try? store.save(data)
        }
    }

    /// Move the currently-shown entry into the archive, retaining its checked
    /// state (R11, R15).
    private func archiveCurrent() {
        guard let id = currentEntryID, var data = try? store.load() else { return }
        guard let idx = data.entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = data.entries[idx]
        entry.points = model.points
        data.entries.remove(at: idx)
        data.archive.append(entry)
        try? store.save(data)
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

    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }
}
