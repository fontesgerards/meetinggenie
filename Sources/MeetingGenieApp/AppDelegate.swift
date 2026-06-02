import AppKit
import NotchCore
import Sparkle

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
    private var hoverSensor: NotchHoverSensor?
    // Sparkle in-app auto-update (U2). Held strongly; starts a background check
    // against the https appcast in Info.plist — the app's only network call.
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        setupStatusItem()
        controller.onArchiveChanged = { [weak self] in self?.rebuildMenu() }

        scheduler = Scheduler(
            store: store,
            onTrigger: { [weak self] entry in
                self?.controller.handleTrigger(entry) // non-interrupting if browsing (R11)
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

        // Idle-notch hover invocation (U4b). The menu item is the primary path;
        // hover is an accelerator.
        let sensor = NotchHoverSensor()
        sensor.onEnter = { [weak self] in self?.controller.hoverOpen() }
        sensor.start()
        hoverSensor = sensor

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(reload), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func reload() {
        scheduler?.reload()
        controller.handleScreenChange() // re-home a visible peek on display reconfig (R4)
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

        let review = NSMenuItem(
            title: "Review meetings…",
            action: #selector(reviewMeetings),
            keyEquivalent: ""
        )
        review.target = self // R9-menu: opens browse at the nearest entry
        menu.addItem(review)

        // Hide-while-sharing toggle (U5; R6, R10). Grouped with "Review meetings…"
        // as the peek controls; the checkmark reflects current suppression state.
        let hide = NSMenuItem(
            title: "Hide while sharing",
            action: #selector(toggleHideWhileSharing),
            keyEquivalent: ""
        )
        hide.target = self
        hide.state = controller.suppressed ? .on : .off
        menu.addItem(hide)

        menu.addItem(.separator())

        let checkUpdates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkUpdates.target = updaterController // Sparkle's built-in action — no forwarding helper
        menu.addItem(checkUpdates)

        let quit = NSMenuItem(
            title: "Quit MeetingGenie",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func reviewMeetings() {
        controller.enterBrowse()
    }

    @objc private func toggleHideWhileSharing() {
        controller.setSuppressed(!controller.suppressed)
        rebuildMenu() // refresh the checkmark
    }

    @objc private func reopen() {
        controller.reopenLastArchivedToday()
        rebuildMenu()
    }
}
