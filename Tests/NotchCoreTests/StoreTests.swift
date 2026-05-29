import Testing
import Foundation
@testable import NotchCore

private func tempStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("notch-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("store.json")
}

@Suite struct StoreTests {
    @Test func loadMissingReturnsEmpty() throws {
        #expect(try Store(url: tempStoreURL()).load() == StoreData())
    }

    @Test func roundTripPreservesEntries() throws {
        let store = Store(url: tempStoreURL())
        let data = StoreData(entries: [
            Entry(startTime: Date(timeIntervalSince1970: 1_000_000), points: [Point(text: "budget")])
        ])
        try store.save(data)
        #expect(try store.load() == data)
    }

    @Test func storeHoldsOnlyTimesAndText() throws {
        // Covers AE5: inspecting the file shows only times and point text.
        let url = tempStoreURL()
        try Store(url: url).save(StoreData(entries: [
            Entry(startTime: Date(timeIntervalSince1970: 1_000_000), points: [Point(text: "ask Q3")])
        ]))
        let json = try String(contentsOf: url, encoding: .utf8).lowercased()
        for forbidden in ["calendar", "attendee", "title", "zoom", "meet", "email"] {
            #expect(!json.contains(forbidden), "store leaked '\(forbidden)'")
        }
        #expect(json.contains("starttime"))
        #expect(json.contains("ask q3"))
    }

    @Test func fileWrittenWith0600() throws {
        let url = tempStoreURL()
        try Store(url: url).save(StoreData())
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(perms?.int16Value == 0o600)
    }

    @Test func archiveRetainedAcrossSaves() throws {
        let store = Store(url: tempStoreURL())
        let archived = Entry(startTime: Date(timeIntervalSince1970: 500), points: [Point(text: "old", checked: true)])
        try store.save(StoreData(entries: [], archive: [archived]))
        let reloaded = try store.load()
        #expect(reloaded.archive == [archived])
        #expect(reloaded.archive[0].points[0].checked)
    }
}
