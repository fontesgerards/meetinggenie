import Foundation
import NotchCore

// CLT-runnable smoke verification for NotchCore.
//
// `swift test` needs full Xcode (XCTest / Swift Testing frameworks), which is
// not present in a Command Line Tools-only environment. This executable
// exercises the same invariants as Tests/NotchCoreTests so the core can be
// verified with `swift run selfcheck`. The XCTest/Swift Testing suite remains
// the authoritative suite when opened in Xcode.

var failures = 0
func check(_ label: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("  ok   \(label)")
    } else {
        print("  FAIL \(label)")
        failures += 1
    }
}

func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("selfcheck-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("store.json")
}

// MARK: Validation / sanitization (R16, R18)
print("Validation:")
check("normal text passes", (try? Validation.validatePoint("raise budget")) == "raise budget")
check("trims whitespace", (try? Validation.validatePoint("  ask Q3  ")) == "ask Q3")
check("empty after sanitize throws", (try? Validation.validatePoint("   ")) == nil)
check("over-length throws", (try? Validation.validatePoint(String(repeating: "x", count: Limits.maxPointLength + 1))) == nil)
let deRLO = (try? Validation.validatePoint("approve\u{202E}contract")) ?? ""
check("strips U+202E RLO override", deRLO == "approvecontract")
check("JSON-like text kept literal", (try? Validation.validatePoint(#"{"checked":true}"#)) == #"{"checked":true}"#)

// MARK: Store (R1–R3, R15, R17; AE5)
print("Store:")
do {
    let url = tempURL()
    let store = Store(url: url)
    check("missing store loads empty", (try? store.load()) == StoreData())

    let entry = Entry(startTime: Date(timeIntervalSince1970: 1_000_000), points: [Point(text: "budget")])
    try store.save(StoreData(entries: [entry]))
    check("round-trips entries", (try? store.load()) == StoreData(entries: [entry]))

    let json = (try? String(contentsOf: url, encoding: .utf8))?.lowercased() ?? ""
    let leaks = ["calendar", "attendee", "title", "zoom", "meet", "email"].filter { json.contains($0) }
    check("AE5: no calendar/platform fields", leaks.isEmpty)

    let perms = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
    check("written 0600", perms?.int16Value == 0o600)

    let archived = Entry(startTime: Date(timeIntervalSince1970: 500), points: [Point(text: "old", checked: true)])
    try store.save(StoreData(archive: [archived]))
    check("archive retained with checked state", (try? store.load())?.archive == [archived])
} catch {
    print("  FAIL Store threw: \(error)"); failures += 1
}

// MARK: StoreService (R5, R16; F1)
print("StoreService:")
do {
    let svc = StoreService(store: Store(url: tempURL()))
    let twoPM = Date(timeIntervalSince1970: 1_700_000_000)
    let entry = try svc.createEntry(at: twoPM, points: ["raise budget", "ask Q3"])
    check("F1: creates entry with two unchecked points", entry.points.map(\.text) == ["raise budget", "ask Q3"] && !entry.points.contains { $0.checked })
    try svc.addPoint(at: twoPM, text: "hiring")
    check("adds a point", (try? svc.list().first?.points.count) == 3)
    try svc.removePoint(at: twoPM, index: 1)
    check("removes a point", (try? svc.list().first?.points.map(\.text)) == ["ask Q3", "hiring"])
    let overCap = (0...Limits.maxPointsPerEntry).map { "p\($0)" }
    check("over-cap create throws", (try? svc.createEntry(at: twoPM, points: overCap)) == nil)
    try svc.clear()
    check("clear empties active entries", (try? svc.list().isEmpty) == true)
} catch {
    print("  FAIL StoreService threw: \(error)"); failures += 1
}

// MARK: TimeParser
print("TimeParser:")
let cal = Calendar(identifier: .gregorian)
let ref = Date(timeIntervalSince1970: 1_700_000_000)
func hm(_ s: String) -> (Int, Int)? {
    guard let d = TimeParser.parse(s, on: ref, calendar: cal) else { return nil }
    let c = cal.dateComponents([.hour, .minute], from: d)
    return (c.hour!, c.minute!)
}
check("parses 2:00pm -> 14:00", hm("2:00pm").map { $0 == (14, 0) } == true)
check("parses 9am -> 09:00", hm("9am").map { $0 == (9, 0) } == true)
check("parses 14:30", hm("14:30").map { $0 == (14, 30) } == true)
check("parses leading-zero 09:00am", hm("09:00am").map { $0 == (9, 0) } == true)
check("parses leading-zero 02:00pm", hm("02:00pm").map { $0 == (14, 0) } == true)
check("rejects garbage", hm("not-a-time") == nil)
check("rejects out-of-range 13pm", TimeParser.parse("13pm", on: ref, calendar: cal) == nil)
check("rejects out-of-range 24:00", TimeParser.parse("24:00", on: ref, calendar: cal) == nil)
check("rejects out-of-range 25:99", TimeParser.parse("25:99", on: ref, calendar: cal) == nil)
check("TimeFormatting round-trips 14:00 -> 2:00pm", TimeFormatting.display(TimeParser.parse("2:00pm", on: ref, calendar: cal)!) == "2:00pm")

// MARK: StoreService entry-by-id ops (R12, R13, R16, R22)
print("StoreService (entry-by-id):")
do {
    let svc = StoreService(store: Store(url: tempURL()))
    let two = Date() // "today" so the reopen-today filter applies
    let entry = try svc.createEntry(at: two, points: ["a", "b"])
    try svc.setChecked(entryID: entry.id, index: 0, checked: true)
    check("setChecked persists by id", svc.entry(id: entry.id)?.points.first?.checked == true)
    try svc.addPoint(entryID: entry.id, text: "c")
    check("addPoint(by id) appends", svc.entry(id: entry.id)?.points.count == 3)
    // cap enforced against fresh store count, not a stale snapshot
    try? svc.addPoint(entryID: entry.id, text: "d")
    try? svc.addPoint(entryID: entry.id, text: "e")
    try? svc.addPoint(entryID: entry.id, text: "f")
    try? svc.addPoint(entryID: entry.id, text: "g") // now at cap (7)
    check("addPoint over cap throws", (try? svc.addPoint(entryID: entry.id, text: "h")) == nil && svc.entry(id: entry.id)?.points.count == Limits.maxPointsPerEntry)
    try svc.archive(entryID: entry.id)
    check("archive removes from active", (try? svc.list().isEmpty) == true)
    check("hasReopenableToday true after archive", svc.hasReopenableToday())
    let reopened = try svc.reopenLatestArchivedToday()
    check("reopen restores entry with checked state", reopened?.id == entry.id && reopened?.points.first?.checked == true)
    check("reopen moves it back to active", (try? svc.list().count) == 1)
} catch {
    print("  FAIL StoreService entry-by-id threw: \(error)"); failures += 1
}

// MARK: StoreWatcher (R7)
print("StoreWatcher:")
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("selfcheck-watch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("store.json")
    let store = Store(url: url)
    try store.save(StoreData())

    let sem = DispatchSemaphore(value: 0)
    let watcher = StoreWatcher(url: url, queue: DispatchQueue(label: "selfcheck.watch")) { sem.signal() }
    watcher.start()
    Thread.sleep(forTimeInterval: 0.2)
    try store.save(StoreData(entries: [Entry(startTime: Date(), points: [Point(text: "new")])]))
    let fired = sem.wait(timeout: .now() + 3) == .success
    check("R7: fires on atomic write", fired)

    // second write after re-arm
    Thread.sleep(forTimeInterval: 0.2)
    try store.save(StoreData(entries: [Entry(startTime: Date()), Entry(startTime: Date())]))
    let firedAgain = sem.wait(timeout: .now() + 3) == .success
    check("R7: re-arms and fires on second atomic write", firedAgain)
    watcher.stop()
} catch {
    print("  FAIL StoreWatcher threw: \(error)"); failures += 1
}

print("")
if failures == 0 {
    print("selfcheck: ALL PASS")
    exit(0)
} else {
    print("selfcheck: \(failures) FAILURE(S)")
    exit(1)
}
