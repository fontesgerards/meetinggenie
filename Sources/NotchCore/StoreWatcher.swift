import Foundation

/// Watches the store file for changes so the running app picks up CLI writes
/// without a restart (origin R7). Uses a `DispatchSource` file-system-object
/// source — lighter than FSEvents for a single file.
///
/// The store writes atomically (temp + rename), which detaches the original
/// inode the descriptor points at. So on `.rename`/`.delete` the watcher tears
/// down and re-arms against the new inode at the same path — the standard
/// failure mode for watching atomically-rewritten files (flagged in plan
/// review). If the file does not exist yet, `start()` polls until it appears.
public final class StoreWatcher {
    private let url: URL
    private let queue: DispatchQueue
    private let onChange: () -> Void

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var stopped = false

    public init(url: URL, queue: DispatchQueue = .main, onChange: @escaping () -> Void) {
        self.url = url
        self.queue = queue
        self.onChange = onChange
    }

    public func start() {
        stopped = false
        arm()
    }

    public func stop() {
        stopped = true
        source?.cancel()
        source = nil
    }

    deinit { stop() }

    private func arm() {
        guard !stopped else { return }
        source?.cancel()
        source = nil

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // File not present yet — retry shortly so pre-launch writes are caught.
            queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.arm() }
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            self.onChange()
            if flags.contains(.rename) || flags.contains(.delete) {
                // Atomic replace swapped the inode — re-arm on the new file.
                self.arm()
            }
        }
        let fd = descriptor
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }
}
