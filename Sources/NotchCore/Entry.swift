import Foundation

/// A single talking point the user wants to raise in a meeting.
///
/// Per origin R1/R2 the only persisted fields are the note text and its
/// checked state — there is deliberately no calendar, attendee, or
/// platform-derived data anywhere in the model (R2, R4, AE5).
public struct Point: Codable, Equatable, Identifiable {
    public var id: UUID
    public var text: String
    public var checked: Bool

    public init(id: UUID = UUID(), text: String, checked: Bool = false) {
        self.id = id
        self.text = text
        self.checked = checked
    }

    // Stable identity gives SwiftUI a reliable per-row key so removing a point
    // doesn't shift per-row state onto a neighbor. Decodes a fresh id when an
    // older store predates the field.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.text = try c.decode(String.self, forKey: .text)
        self.checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
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
