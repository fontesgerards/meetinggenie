import Testing
import Foundation
@testable import NotchCore

@Suite struct StoreWatcherTests {
    private func freshStore() throws -> (Store, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("store.json")
        let store = Store(url: url)
        try store.save(StoreData()) // must exist before arming
        return (store, url)
    }

    @Test func firesOnAtomicWrite() async throws {
        let (store, url) = try freshStore()
        await confirmation("watcher fires on change", expectedCount: 1...) { confirmed in
            let watcher = StoreWatcher(url: url, queue: DispatchQueue(label: "watch.test")) {
                confirmed()
            }
            watcher.start()
            try? await Task.sleep(for: .milliseconds(200)) // let the source arm
            try? store.save(StoreData(entries: [Entry(startTime: Date(), points: [Point(text: "new")])]))
            try? await Task.sleep(for: .seconds(2)) // allow the event to deliver
            watcher.stop()
        }
    }

    @Test func reArmsAfterRenameAndFiresAgain() async throws {
        let (store, url) = try freshStore()
        await confirmation("watcher re-arms across atomic writes", expectedCount: 2...) { confirmed in
            let watcher = StoreWatcher(url: url, queue: DispatchQueue(label: "watch.rearm")) {
                confirmed()
            }
            watcher.start()
            try? await Task.sleep(for: .milliseconds(200))
            try? store.save(StoreData(entries: [Entry(startTime: Date())]))
            try? await Task.sleep(for: .seconds(1)) // first atomic-rename write
            try? store.save(StoreData(entries: [Entry(startTime: Date()), Entry(startTime: Date())]))
            try? await Task.sleep(for: .seconds(2)) // second write after re-arm
            watcher.stop()
        }
    }
}
