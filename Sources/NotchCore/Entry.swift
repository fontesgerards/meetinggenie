import Foundation

/// A single talking point the user wants to raise in a meeting.
///
/// Per origin R1/R2 the only persisted fields are the note text and its
/// checked state — there is deliberately no calendar, attendee, or
/// platform-derived data anywhere in the model (R2, R4, AE5).
public struct Point: Codable, Equatable {
    public var text: String
    public var checked: Bool

    public init(text: String, checked: Bool = false) {
        self.text = text
        self.checked = checked
    }
}

/// An entry is a start time plus a list of points (origin R1).
public struct Entry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var startTime: Date
    public var points: [Point]

    public init(id: UUID = UUID(), startTime: Date, points: [Point] = []) {
        self.id = id
        self.startTime = startTime
        self.points = points
    }
}

/// The whole persisted store: upcoming/active entries plus the retained
/// archive. Archived entries are kept indefinitely (origin R15) — there is
/// no purge in v1.
public struct StoreData: Codable, Equatable {
    public var entries: [Entry]
    public var archive: [Entry]

    public init(entries: [Entry] = [], archive: [Entry] = []) {
        self.entries = entries
        self.archive = archive
    }
}
