import Foundation

/// The display inverse of `TimeParser`, kept beside it so the format and its
/// inverse stay in sync. Both the CLI and the app render entry times through
/// this, rather than each hand-rolling a `DateFormatter`.
public enum TimeFormatting {
    public static func display(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }
}
