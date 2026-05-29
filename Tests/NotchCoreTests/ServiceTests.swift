import Testing
import Foundation
@testable import NotchCore

private func makeService() -> StoreService {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("notch-svc-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("store.json")
    return StoreService(store: Store(url: url))
}

private let twoPM = Date(timeIntervalSince1970: 1_700_000_000)
private let twoThirty = Date(timeIntervalSince1970: 1_700_001_800)

@Suite struct ServiceTests {
    @Test func createEntryWithPoints() throws {
        // Covers F1: agent creates an entry with two unchecked points.
        let svc = makeService()
        let entry = try svc.createEntry(at: twoPM, points: ["raise budget", "ask Q3 timeline"])
        #expect(entry.points.map(\.text) == ["raise budget", "ask Q3 timeline"])
        #expect(!entry.points.contains { $0.checked })
        #expect(try svc.list().count == 1)
    }

    @Test func createReplacesSameTimeEntry() throws {
        let svc = makeService()
        try svc.createEntry(at: twoPM, points: ["first"])
        try svc.createEntry(at: twoPM, points: ["second"])
        let entries = try svc.list()
        #expect(entries.count == 1)
        #expect(entries[0].points.map(\.text) == ["second"])
    }

    @Test func addThenRemovePoint() throws {
        let svc = makeService()
        try svc.createEntry(at: twoPM, points: ["one"])
        try svc.addPoint(at: twoPM, text: "two")
        #expect(try svc.list()[0].points.map(\.text) == ["one", "two"])
        try svc.removePoint(at: twoPM, index: 1)
        #expect(try svc.list()[0].points.map(\.text) == ["two"])
    }

    @Test func removeEntryAndClear() throws {
        let svc = makeService()
        try svc.createEntry(at: twoPM, points: ["a"])
        try svc.createEntry(at: twoThirty, points: ["b"])
        try svc.removeEntry(at: twoPM)
        #expect(try svc.list().count == 1)
        try svc.clear()
        #expect(try svc.list().isEmpty)
    }

    @Test func createRejectsOverCapAndWritesNothing() throws {
        let svc = makeService()
        let tooMany = (0...Limits.maxPointsPerEntry).map { "point \($0)" } // max + 1
        #expect(throws: ValidationError.tooManyPoints(max: Limits.maxPointsPerEntry)) {
            try svc.createEntry(at: twoPM, points: tooMany)
        }
        #expect(try svc.list().isEmpty)
    }

    @Test func addPointRejectsOverCap() throws {
        let svc = makeService()
        let atCap = (1...Limits.maxPointsPerEntry).map { "p\($0)" }
        try svc.createEntry(at: twoPM, points: atCap)
        #expect(throws: ValidationError.tooManyPoints(max: Limits.maxPointsPerEntry)) {
            try svc.addPoint(at: twoPM, text: "overflow")
        }
    }

    @Test func addPointToMissingEntryThrows() {
        let svc = makeService()
        #expect(throws: (any Error).self) {
            try svc.addPoint(at: twoPM, text: "x")
        }
    }

    // MARK: entry-by-id ops used by the app

    @Test func setCheckedAndAddPointByID() throws {
        let svc = makeService()
        let entry = try svc.createEntry(at: twoPM, points: ["a", "b"])
        try svc.setChecked(entryID: entry.id, index: 0, checked: true)
        #expect(svc.entry(id: entry.id)?.points.first?.checked == true)
        try svc.addPoint(entryID: entry.id, text: "c")
        #expect(svc.entry(id: entry.id)?.points.count == 3)
    }

    @Test func addPointByIDEnforcesCapAgainstFreshStore() throws {
        let svc = makeService()
        let atCap = (1...Limits.maxPointsPerEntry).map { "p\($0)" }
        let entry = try svc.createEntry(at: twoPM, points: atCap)
        #expect(throws: ValidationError.tooManyPoints(max: Limits.maxPointsPerEntry)) {
            try svc.addPoint(entryID: entry.id, text: "overflow")
        }
    }

    @Test func archiveThenReopenToday() throws {
        let svc = makeService()
        let entry = try svc.createEntry(at: Date(), points: ["a"]) // today
        try svc.setChecked(entryID: entry.id, index: 0, checked: true)
        try svc.archive(entryID: entry.id)
        #expect(try svc.list().isEmpty)
        #expect(svc.hasReopenableToday())
        let reopened = try svc.reopenLatestArchivedToday()
        #expect(reopened?.id == entry.id)
        #expect(reopened?.points.first?.checked == true)
        #expect(try svc.list().count == 1)
    }

    @Test func archivedEntryFromAnotherDayIsNotReopenableToday() throws {
        let svc = makeService()
        let entry = try svc.createEntry(at: Date(timeIntervalSince1970: 1_000_000), points: ["old"])
        try svc.archive(entryID: entry.id)
        #expect(!svc.hasReopenableToday())
        #expect(try svc.reopenLatestArchivedToday() == nil)
    }
}

@Suite struct TimeParserTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    private func hm(_ date: Date?) -> (Int, Int)? {
        guard let date else { return nil }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour!, c.minute!)
    }

    @Test func parsesTwelveHourPM() {
        #expect(hm(TimeParser.parse("2:00pm", on: reference, calendar: calendar))! == (14, 0))
    }

    @Test func parsesHourOnlyAMPM() {
        #expect(hm(TimeParser.parse("9am", on: reference, calendar: calendar))! == (9, 0))
    }

    @Test func parsesTwentyFourHour() {
        #expect(hm(TimeParser.parse("14:30", on: reference, calendar: calendar))! == (14, 30))
    }

    @Test func rejectsGarbage() {
        #expect(TimeParser.parse("not-a-time", on: reference, calendar: calendar) == nil)
    }

    @Test func rejectsOutOfRangeTimes() {
        // DateFormatter would silently "fix up" these; the round-trip guard rejects them.
        #expect(TimeParser.parse("13pm", on: reference, calendar: calendar) == nil)
        #expect(TimeParser.parse("24:00", on: reference, calendar: calendar) == nil)
        #expect(TimeParser.parse("25:99", on: reference, calendar: calendar) == nil)
    }

    @Test func displayIsInverseOfParse() {
        let date = TimeParser.parse("2:00pm", on: reference, calendar: calendar)!
        #expect(TimeFormatting.display(date) == "2:00pm")
    }
}
