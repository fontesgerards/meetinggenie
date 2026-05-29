import Foundation

/// Reads and writes the local JSON store (origin R1–R3, R17).
///
/// - Location: `~/Library/Application Support/MeetingGenie/store.json` by
///   default; injectable for tests.
/// - Permissions: written `0600` (owner read/write only).
/// - Atomicity: `Data.write(options: .atomic)` writes to a sibling temp file
///   and renames over the destination, so a crash mid-write never leaves a
///   partial file. (The rename is why `StoreWatcher` must handle `.rename`.)
/// - Backup: excluded from iCloud/Time Machine via `isExcludedFromBackup`
///   (resolves the Time Machine question raised in plan review).
public final class Store {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? Store.defaultURL()
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("MeetingGenie", isDirectory: true)
            .appendingPathComponent("store.json")
    }

    public func load() throws -> StoreData {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return StoreData()
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return StoreData() }
        return try Self.decoder.decode(StoreData.self, from: data)
    }

    public func save(_ store: StoreData) throws {
        try ensureDirectory()
        let data = try Self.encoder.encode(store)

        // Write to a sibling temp file that is created 0600 *before* any bytes
        // land, then atomically move it into place. This closes the window
        // where Data.write(.atomic) would briefly expose the notes at the
        // umask default (0644), and guarantees a crash never leaves a
        // world-readable store (R17).
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".store.\(UUID().uuidString).tmp")
        let fm = FileManager.default
        fm.createFile(atPath: tmp.path, contents: nil, attributes: [.posixPermissions: 0o600])
        do {
            try data.write(to: tmp) // in-place write preserves the 0600 perms
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
        // replaceItemAt may adopt the destination's metadata; re-assert 0600.
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        excludeFromBackup()
    }

    // MARK: - Helpers

    private func ensureDirectory() throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func excludeFromBackup() {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
