import Testing
import Foundation
@testable import NotchCore

@Suite struct ReviewSequenceTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ offsetSeconds: TimeInterval, _ text: String, checked: Bool = false) -> Entry {
        Entry(startTime: now.addingTimeInterval(offsetSeconds), points: [Point(text: text, checked: checked)])
    }

    @Test func ordersPastActiveUpcomingByTime() {
        let data = StoreData(
            entries: [entry(3600, "in 1h"), entry(-60, "started")],   // upcoming, active
            archive: [entry(-3600, "an hour ago")]                    // past
        )
        let seq = ReviewSequence.build(from: data, now: now)
        #expect(seq.map(\.kind) == [.past, .active, .upcoming])
        #expect(seq.map { $0.entry.points.first?.text } == ["an hour ago", "started", "in 1h"])
    }

    @Test func classifiesActiveVsUpcomingByStartTime() {
        let data = StoreData(entries: [entry(-1, "due"), entry(1, "soon")])
        let seq = ReviewSequence.build(from: data, now: now)
        #expect(seq.first(where: { $0.entry.points.first?.text == "due" })?.kind == .active)
        #expect(seq.first(where: { $0.entry.points.first?.text == "soon" })?.kind == .upcoming)
    }

    @Test func preservesArchivedCheckedState() {
        let data = StoreData(archive: [
            Entry(startTime: now.addingTimeInterval(-100),
                  points: [Point(text: "raised", checked: true), Point(text: "missed", checked: false)])
        ])
        let seq = ReviewSequence.build(from: data, now: now)
        #expect(seq.count == 1 && seq[0].kind == .past)
        #expect(seq[0].entry.points.map(\.checked) == [true, false])
    }

    @Test func excludesArchiveOlderThanWindowAndIncludesEdge() {
        let window: TimeInterval = 7 * 24 * 60 * 60
        let data = StoreData(archive: [
            entry(-window - 1, "too old"),
            entry(-window, "at edge"),
        ])
        let seq = ReviewSequence.build(from: data, now: now, window: window)
        let texts = seq.map { $0.entry.points.first?.text }
        #expect(texts.contains("at edge"))
        #expect(!texts.contains("too old"))
    }

    @Test func emptyStoreYieldsEmptySequence() {
        #expect(ReviewSequence.build(from: StoreData(), now: now).isEmpty)
    }
}

@Suite struct RemovePointByIDTests {
    private func service() -> StoreService {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-rm-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("store.json")
        return StoreService(store: Store(url: url))
    }

    @Test func removesTargetedPoint() throws {
        let svc = service()
        let e = try svc.createEntry(at: Date(timeIntervalSince1970: 1_700_000_000), points: ["a", "b", "c"])
        try svc.removePoint(entryID: e.id, index: 1)
        #expect(svc.entry(id: e.id)?.points.map(\.text) == ["a", "c"])
    }

    @Test func outOfRangeIndexThrows() throws {
        let svc = service()
        let e = try svc.createEntry(at: Date(timeIntervalSince1970: 1_700_000_000), points: ["only"])
        #expect(throws: ServiceError.noPoint(index: 5)) {
            try svc.removePoint(entryID: e.id, index: 5)
        }
    }

    @Test func removingLastPointLeavesEmptyEntry() throws {
        let svc = service()
        let e = try svc.createEntry(at: Date(timeIntervalSince1970: 1_700_000_000), points: ["solo"])
        try svc.removePoint(entryID: e.id, index: 0)
        #expect(svc.entry(id: e.id)?.points.isEmpty == true)
    }
}
