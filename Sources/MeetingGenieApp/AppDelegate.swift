import AppKit
import NotchCore

/// Wires the menu-bar agent together (plan unit U5): status item + menu,
/// scheduler, file watcher, and the peek controller. Re-arms on wake, clock
/// change, and display reconfiguration.
@available(macOS 13, *)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private lazy var service = StoreService(store: store)
    private lazy var controller = PeekController(service: service)
    private var scheduler: Scheduler?
    private var watcher: StoreWatcher?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        controller.onArchiveChanged = { [weak self] in self?.rebuildMenu() }

        scheduler = Scheduler(
            store: store,
            onTrigger: { [weak self] entry in
                self?.controller.show(entry)
                self?.rebuildMenu()
            },
            onMidnight: { [weak self] in
                self?.controller.dismissForMidnight()
                self?.rebuildMenu()
            }
        )

        // Live pickup of CLI writes (R7).
        watcher = StoreWatcher(url: store.url, queue: .main) { [weak self] in
            self?.scheduler?.reload()
            self?.rebuildMenu()
        }
        watcher?.start()
        scheduler?.reload()

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(reload), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func reload() {
        scheduler?.reload()
        rebuildMenu()
    }

    // MARK: - Status item / menu

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "MeetingGenie")
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false // honor our explicit isEnabled below

        let reopen = NSMenuItem(
            title: "Re-open last meeting's points",
            action: #selector(reopen),
            keyEquivalent: ""
        )
        reopen.target = self
        reopen.isEnabled = controller.hasReopenableEntryToday() // R22 / P0 resolution
        menu.addItem(reopen)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit MeetingGenie",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func reopen() {
        controller.reopenLastArchivedToday()
        rebuildMenu()
    }
}
