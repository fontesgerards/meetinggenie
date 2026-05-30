import Foundation

/// Where an entry sits relative to now (origin R2). Drives the peek's
/// per-recency action gating (R5/R7/R8) while browsing.
public enum ReviewKind: Equatable {
    case past      // archived (history) — read-only, shows raised/missed
    case active    // active-set, start time reached — full actions
    case upcoming  // active-set, start time in the future — correctable
}

/// One entry in the browseable nearby sequence.
public struct ReviewItem: Equatable {
    public let entry: Entry
    public let kind: ReviewKind

    public init(entry: Entry, kind: ReviewKind) {
        self.entry = entry
        self.kind = kind
    }
}

/// Assembles the time-ordered "nearby meetings" sequence the peek pages through
/// (origin R1, R4). AppKit-free and pure so it is headlessly testable.
public enum ReviewSequence {
    /// How far back archived entries are included, so paging isn't endless.
    public static let defaultWindow: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    /// Build the sequence from store data, sorted ascending by start time:
    /// archived entries within `window` before `now` as `.past`; active-set
    /// entries as `.active` when their start time has been reached, else
    /// `.upcoming`.
    public static func build(
        from data: StoreData,
        now: Date,
        window: TimeInterval = defaultWindow
    ) -> [ReviewItem] {
        let cutoff = now.addingTimeInterval(-window)
        let past = data.archive
            .filter { $0.startTime >= cutoff }
            .map { ReviewItem(entry: $0, kind: .past) }
        let active = data.entries.map { entry in
            ReviewItem(entry: entry, kind: entry.startTime <= now ? .active : .upcoming)
        }
        // Sort by start time, with a deterministic tiebreaker (past < active <
        // upcoming, then id) so equal-time entries keep a stable order.
        func rank(_ kind: ReviewKind) -> Int {
            switch kind { case .past: return 0; case .active: return 1; case .upcoming: return 2 }
        }
        return (past + active).sorted { a, b in
            if a.entry.startTime != b.entry.startTime { return a.entry.startTime < b.entry.startTime }
            if rank(a.kind) != rank(b.kind) { return rank(a.kind) < rank(b.kind) }
            return a.entry.id.uuidString < b.entry.id.uuidString
        }
    }
}
