import Foundation
import NotchCore

// The `notch` CLI is the sole agent-facing interface in v1 (origin R5/R6).
// It is local-file only: every subcommand maps to a NotchCore store operation,
// with no network or remote write path (R19). Cap/validation failures exit
// non-zero with a readable message (R16/R18). There is no `edit point text`
// verb — remove-and-re-add covers it (deferred per origin scope).

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("notch: \(message)\n".utf8))
    exit(1)
}

func displayTime(_ date: Date) -> String { TimeFormatting.display(date) }

let usage = """
usage:
  notch add <time> <point>...        create/replace the entry at <time>
  notch add-point <time> <text>      append a point to the entry at <time>
  notch remove-point <time> <n>      remove the nth (1-based) point
  notch remove <time>                remove the entry at <time>
  notch list                         list active entries
  notch clear                        remove all active entries (archive kept)
"""

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage)
    exit(0)
}
let rest = Array(arguments.dropFirst())
let service = StoreService(store: Store())

func requireTime(_ raw: String) -> Date {
    guard let time = TimeParser.parse(raw) else { die("could not parse time '\(raw)'") }
    return time
}

do {
    switch command {
    case "add":
        guard rest.count >= 2 else { die("usage: notch add <time> <point>...") }
        let time = requireTime(rest[0])
        let entry = try service.createEntry(at: time, points: Array(rest.dropFirst()))
        print("added entry at \(displayTime(entry.startTime)) with \(entry.points.count) point(s)")

    case "add-point":
        guard rest.count >= 2 else { die("usage: notch add-point <time> <text>") }
        let time = requireTime(rest[0])
        try service.addPoint(at: time, text: rest.dropFirst().joined(separator: " "))
        print("added point to entry at \(displayTime(time))")

    case "remove-point":
        guard rest.count == 2, let n = Int(rest[1]) else { die("usage: notch remove-point <time> <n>") }
        let time = requireTime(rest[0])
        try service.removePoint(at: time, index: n)
        print("removed point \(n) from entry at \(displayTime(time))")

    case "remove":
        guard rest.count == 1 else { die("usage: notch remove <time>") }
        let time = requireTime(rest[0])
        try service.removeEntry(at: time)
        print("removed entry at \(displayTime(time))")

    case "list":
        let entries = try service.list()
        if entries.isEmpty {
            print("(no active entries)")
        } else {
            for entry in entries {
                print("\(displayTime(entry.startTime)):")
                for (i, point) in entry.points.enumerated() {
                    print("  \(i + 1). [\(point.checked ? "x" : " ")] \(point.text)")
                }
            }
        }

    case "clear":
        try service.clear()
        print("cleared active entries")

    case "-h", "--help", "help":
        print(usage)

    default:
        die("unknown command '\(command)'\n\(usage)")
    }
} catch let error as ValidationError {
    die(error.description)
} catch let error as ServiceError {
    die(error.description)
} catch {
    die("\(error)")
}
