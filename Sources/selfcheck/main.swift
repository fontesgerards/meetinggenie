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
    // `title` is now a legitimate user/agent-authored field, so it is no longer
    // in the leak list — only calendar/platform-derived fields stay banned (AE5).
    let leaks = ["calendar", "attendee", "zoom", "meet", "email"].filter { json.contains($0) }
    check("AE5: no calendar/platform fields", leaks.isEmpty)

    let perms = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
    check("written 0600", perms?.int16Value == 0o600)

    let archived = Entry(startTime: Date(timeIntervalSince1970: 500), points: [Point(text: "old", checked: true)])
    try store.save(StoreData(archive: [archived]))
    check("archive retained with checked state", (try? store.load())?.archive == [archived])

    // R9: titled entry round-trips, and AE5 stays green with a title present.
    let titledURL = tempURL()
    let titledStore = Store(url: titledURL)
    let titled = Entry(startTime: Date(timeIntervalSince1970: 2_000), points: [Point(text: "p")], title: "Q3 Sync")
    try titledStore.save(StoreData(entries: [titled]))
    check("R9: title round-trips", (try? titledStore.load())?.entries.first?.title == "Q3 Sync")
    let titledJSON = (try? String(contentsOf: titledURL, encoding: .utf8))?.lowercased() ?? ""
    check("AE5: still green with a title present", !["calendar", "attendee", "zoom", "meet", "email"].contains { titledJSON.contains($0) })

    // R9: a legacy store JSON with no `title` key decodes with title == nil.
    let legacy = #"{"entries":[{"id":"\#(UUID().uuidString)","startTime":0,"points":[{"id":"\#(UUID().uuidString)","text":"x","checked":false}]}],"archive":[]}"#
    let decoded = try? JSONDecoder().decode(StoreData.self, from: Data(legacy.utf8))
    check("R9: legacy titleless entry decodes to nil title", decoded?.entries.first != nil && decoded?.entries.first?.title == nil)
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

// MARK: Title validation + StoreService title ops (R3–R7)
print("Title:")
check("validateTitle trims + keeps text", (try? Validation.validateTitle("  Q3 Sync  ")) == "Q3 Sync")
check("validateTitle empty -> nil (clear)", (try? Validation.validateTitle("   ")) == .some(nil))
check("validateTitle 60 chars accepted", (try? Validation.validateTitle(String(repeating: "x", count: Limits.maxTitleLength))) == .some(String(repeating: "x", count: 60)))
check("validateTitle 61 chars throws", (try? Validation.validateTitle(String(repeating: "x", count: Limits.maxTitleLength + 1))) == nil)
check("validateTitle strips RLO override", (try? Validation.validateTitle("Q3\u{202E}Sync")) == "Q3Sync")
do {
    let svc = StoreService(store: Store(url: tempURL()))
    let t = Date(timeIntervalSince1970: 1_700_000_000)
    let created = try svc.createEntry(at: t, points: ["p"], title: "Q3 Sync")
    check("createEntry sets title", created.title == "Q3 Sync")
    let preserved = try svc.createEntry(at: t, points: ["p", "q"], title: nil) // not supplied
    check("re-add without title preserves it", preserved.title == "Q3 Sync" && preserved.points.count == 2)
    let cleared = try svc.createEntry(at: t, points: ["p"], title: "") // supplied empty -> clear
    check("re-add with empty title clears it", cleared.title == nil)
    try svc.setTitle(at: t, title: "Renamed")
    let afterRename = try svc.list()
    check("setTitle(at:) sets", afterRename.first?.title == "Renamed")
    try svc.setTitle(at: t, title: "")
    let afterClear = try svc.list()
    check("setTitle(at:) empty clears", afterClear.count == 1 && afterClear.first?.title == nil)
    check("setTitle(at:) missing time throws", (try? svc.setTitle(at: Date(timeIntervalSince1970: 5), title: "x")) == nil)
    let id = (try svc.list()).first!.id
    try svc.setTitle(entryID: id, title: "By ID")
    check("setTitle(entryID:) sets", svc.entry(id: id)?.title == "By ID")
    check("setTitle over-length throws, store unchanged", (try? svc.setTitle(entryID: id, title: String(repeating: "x", count: 61))) == nil && svc.entry(id: id)?.title == "By ID")
} catch {
    print("  FAIL Title StoreService threw: \(error)"); failures += 1
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

// MARK: ReviewSequence + removePoint(entryID:) (R1, R2, R4, R5)
print("ReviewSequence:")
do {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    func e(_ off: TimeInterval, _ t: String, checked: Bool = false) -> Entry {
        Entry(startTime: base.addingTimeInterval(off), points: [Point(text: t, checked: checked)])
    }
    let data = StoreData(
        entries: [e(3600, "in 1h"), e(-60, "started")],
        archive: [e(-3600, "an hour ago", checked: true)]
    )
    let seq = ReviewSequence.build(from: data, now: base)
    check("orders past→active→upcoming", seq.map(\.kind) == [.past, .active, .upcoming])
    check("past entry keeps checked state", seq.first?.entry.points.first?.checked == true)
    let windowed = ReviewSequence.build(
        from: StoreData(archive: [e(-(8 * 24 * 3600), "too old"), e(-(6 * 24 * 3600), "recent")]),
        now: base
    )
    check("excludes archive older than 7-day window", windowed.map { $0.entry.points.first?.text } == ["recent"])
    check("empty store → empty sequence", ReviewSequence.build(from: StoreData(), now: base).isEmpty)

    let svc = StoreService(store: Store(url: tempURL()))
    let entry = try svc.createEntry(at: base, points: ["a", "b", "c"])
    try svc.removePoint(entryID: entry.id, index: 1)
    check("removePoint(entryID:) removes the targeted point", svc.entry(id: entry.id)?.points.map(\.text) == ["a", "c"])
    check("removePoint out-of-range throws", (try? svc.removePoint(entryID: entry.id, index: 9)) == nil)
    let editID = svc.entry(id: entry.id)?.points.first?.id
    try svc.updatePoint(entryID: entry.id, index: 0, text: "edited")
    check("updatePoint replaces text, preserves id", svc.entry(id: entry.id)?.points.first?.text == "edited" && svc.entry(id: entry.id)?.points.first?.id == editID)
    check("updatePoint rejects empty text", (try? svc.updatePoint(entryID: entry.id, index: 0, text: "   ")) == nil)
} catch {
    print("  FAIL ReviewSequence threw: \(error)"); failures += 1
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
