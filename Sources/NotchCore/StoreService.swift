import Foundation

/// High-level operations on the store, shared by the CLI (origin R5/R6) and —
/// later — the app's quick-add path so both honor exactly one set of caps and
/// sanitization rules (R16, R18). Entries are addressed by their start time,
/// consistent with the single-active-peek model.
public final class StoreService {
    private let store: Store

    public init(store: Store) {
        self.store = store
    }

    /// Create (or replace) the entry at `startTime` with the given raw point
    /// strings. Validates and sanitizes each point and enforces the per-entry
    /// cap before writing anything (R16, R18).
    @discardableResult
    public func createEntry(at startTime: Date, points rawPoints: [String]) throws -> Entry {
        let cleaned = try rawPoints.map { try Validation.validatePoint($0) }
        if cleaned.count > Limits.maxPointsPerEntry {
            throw ValidationError.tooManyPoints(max: Limits.maxPointsPerEntry)
        }
        var data = try store.load()
        var entry = Entry(startTime: startTime, points: cleaned.map { Point(text: $0) })
        if let idx = data.entries.firstIndex(where: { $0.startTime == startTime }) {
            entry.id = data.entries[idx].id
            data.entries[idx] = entry
        } else {
            data.entries.append(entry)
        }
        try store.save(data)
        return entry
    }

    /// Append a point to the existing entry at `startTime` (R16-capped).
    public func addPoint(at startTime: Date, text: String) throws {
        let clean = try Validation.validatePoint(text)
        var data = try store.load()
        guard let idx = data.entries.firstIndex(where: { $0.startTime == startTime }) else {
            throw ServiceError.noEntry(at: startTime)
        }
        if data.entries[idx].points.count + 1 > Limits.maxPointsPerEntry {
            throw ValidationError.tooManyPoints(max: Limits.maxPointsPerEntry)
        }
        data.entries[idx].points.append(Point(text: clean))
        try store.save(data)
    }

    /// Remove the 1-based `index` point from the entry at `startTime`.
    public func removePoint(at startTime: Date, index oneBased: Int) throws {
        var data = try store.load()
        guard let idx = data.entries.firstIndex(where: { $0.startTime == startTime }) else {
            throw ServiceError.noEntry(at: startTime)
        }
        let pointIndex = oneBased - 1
        guard data.entries[idx].points.indices.contains(pointIndex) else {
            throw ServiceError.noPoint(index: oneBased)
        }
        data.entries[idx].points.remove(at: pointIndex)
        try store.save(data)
    }

    /// Remove the entry at `startTime` entirely.
    public func removeEntry(at startTime: Date) throws {
        var data = try store.load()
        guard let idx = data.entries.firstIndex(where: { $0.startTime == startTime }) else {
            throw ServiceError.noEntry(at: startTime)
        }
        data.entries.remove(at: idx)
        try store.save(data)
    }

    /// Clear all active entries. The retained archive (R15) is left intact.
    public func clear() throws {
        var data = try store.load()
        data.entries = []
        try store.save(data)
    }

    public func list() throws -> [Entry] {
        try store.load().entries.sorted { $0.startTime < $1.startTime }
    }

    /// The time-ordered nearby sequence for browse navigation (R1, R2, R4):
    /// recent archived entries, the active entry, and upcoming queued entries.
    public func reviewSequence(
        now: Date = Date(),
        window: TimeInterval = ReviewSequence.defaultWindow
    ) -> [ReviewItem] {
        guard let data = try? store.load() else { return [] }
        return ReviewSequence.build(from: data, now: now, window: window)
    }

    // MARK: - Entry-by-id operations (used by the app's peek interactions)
    //
    // These read the store fresh on each call and mutate one targeted field, so
    // a concurrent CLI write to the same entry is not clobbered by a stale
    // in-memory snapshot, and the per-entry cap is always checked against the
    // persisted count (R12, R13, R16).

    public func entry(id: UUID) -> Entry? {
        (try? store.load())?.entries.first { $0.id == id }
    }

    public func addPoint(entryID: UUID, text: String) throws {
        let clean = try Validation.validatePoint(text)
        var data = try store.load()
        guard let idx = data.entries.firstIndex(where: { $0.id == entryID }) else {
            throw ServiceError.noEntryID
        }
        if data.entries[idx].points.count + 1 > Limits.maxPointsPerEntry {
            throw ValidationError.tooManyPoints(max: Limits.maxPointsPerEntry)
        }
        data.entries[idx].points.append(Point(text: clean))
        try store.save(data)
    }

    /// Remove the 0-based `index` point from the entry with `entryID`. Removing
    /// the last point leaves an empty entry (which the peek treats as a no-op).
    public func removePoint(entryID: UUID, index: Int) throws {
        var data = try store.load()
        guard let idx = data.entries.firstIndex(where: { $0.id == entryID }) else {
            throw ServiceError.noEntryID
        }
        guard data.entries[idx].points.indices.contains(index) else {
            throw ServiceError.noPoint(index: index)
        }
        data.entries[idx].points.remove(at: index)
        try store.save(data)
    }

    public func setChecked(entryID: UUID, index: Int, checked: Bool) throws {
        var data = try store.load()
        guard let idx = data.entries.firstIndex(where: { $0.id == entryID }),
              data.entries[idx].points.indices.contains(index) else {
            throw ServiceError.noPoint(index: index)
        }
        data.entries[idx].points[index].checked = checked
        try store.save(data)
    }

    /// Move an entry from the active set into the retained archive (R11, R15).
    public func archive(entryID: UUID) throws {
        var data = try store.load()
        guard let idx = data.entries.firstIndex(where: { $0.id == entryID }) else { return }
        let entry = data.entries.remove(at: idx)
        data.archive.append(entry)
        try store.save(data)
    }

    /// Move the most recent archived entry from today back into the active set
    /// and return it (R22). Returns nil if none is eligible.
    @discardableResult
    public func reopenLatestArchivedToday(now: Date = Date(), calendar: Calendar = .current) throws -> Entry? {
        var data = try store.load()
        let candidates = data.archive.enumerated().filter {
            calendar.isDate($0.element.startTime, inSameDayAs: now)
        }
        guard let pick = candidates.max(by: { $0.element.startTime < $1.element.startTime }) else {
            return nil
        }
        let entry = data.archive.remove(at: pick.offset)
        data.entries.append(entry)
        try store.save(data)
        return entry
    }

    public func hasReopenableToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let data = try? store.load() else { return false }
        return data.archive.contains { calendar.isDate($0.startTime, inSameDayAs: now) }
    }
}

public enum ServiceError: Error, Equatable, CustomStringConvertible {
    case noEntry(at: Date)
    case noEntryID
    case noPoint(index: Int)

    public var description: String {
        switch self {
        case .noEntry:
            return "no entry exists at that time"
        case .noEntryID:
            return "no entry exists with that id"
        case .noPoint(let index):
            return "no point at index \(index)"
        }
    }
}
