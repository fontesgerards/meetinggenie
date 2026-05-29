import AppKit

// MeetingGenie menu-bar agent (plan unit U5 entry point).
//
// Runs as an accessory (no Dock icon) via setActivationPolicy(.accessory) —
// the programmatic equivalent of the LSUIElement Info.plist key, so this builds
// and runs as a plain SwiftPM executable without an Xcode app bundle.

guard #available(macOS 13, *) else {
    FileHandle.standardError.write(Data("MeetingGenie requires macOS 13 or later\n".utf8))
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
