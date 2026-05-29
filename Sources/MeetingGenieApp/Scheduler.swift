import Foundation
import NotchCore

/// Arms timers to surface peeks at their start times and a midnight safety-net
/// timer (origin R7, R8, R10; plan unit U5). Re-reads the store on demand —
/// on launch, on file-watch changes, and on wake / clock change — and re-arms.
@available(macOS 13, *)
final class Scheduler {
    private let store: Store
    private let onTrigger: (Entry) -> Void
    private let onMidnight: () -> Void
    private var timers: [Timer] = []
    private var firedEntryIDs = Set<UUID>()

    init(store: Store, onTrigger: @escaping (Entry) -> Void, onMidnight: @escaping () -> Void) {
        self.store = store
        self.onTrigger = onTrigger
        self.onMidnight = onMidnight
    }

    func reload(now: Date = Date(), calendar: Calendar = .current) {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        guard let data = try? store.load() else { return }

        // Entries whose start time already passed (written late, or woke from
        // sleep across them): surface only the MOST RECENT one. Firing every
        // past entry in a single pass would flash and instantly archive all but
        // the last (latest-wins). Mark the rest fired without showing them.
        let duePast = data.entries.filter { !firedEntryIDs.contains($0.id) && $0.startTime <= now }
        if let latest = duePast.max(by: { $0.startTime < $1.startTime }) {
            for entry in duePast { firedEntryIDs.insert(entry.id) }
            onTrigger(latest)
        }

        // Future entries get a timer each.
        for entry in data.entries where !firedEntryIDs.contains(entry.id) && entry.startTime > now {
            let timer = Timer(fire: entry.startTime, interval: 0, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.firedEntryIDs.insert(entry.id)
                self.onTrigger(entry)
            }
            RunLoop.main.add(timer, forMode: .common)
            timers.append(timer)
        }

        if let midnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) {
            let timer = Timer(fire: midnight, interval: 0, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.firedEntryIDs.removeAll() // new day
                self.onMidnight()
                self.reload()
            }
            RunLoop.main.add(timer, forMode: .common)
            timers.append(timer)
        }
    }
}
