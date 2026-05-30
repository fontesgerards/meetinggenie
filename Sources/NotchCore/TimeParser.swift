import Foundation

/// Parses a human time-of-day string ("2:00pm", "2pm", "14:00") into a concrete
/// `Date` on a reference day. The store holds only times (origin R2), and the
/// CLI lets an agent or user express that time loosely.
public enum TimeParser {
    private static let formats = [
        "h:mma", "hh:mma", "h:mm a", "hh:mm a", // 12-hour, with/without leading zero
        "ha", "hha", "h a", "hh a",
        "H:mm", "HH:mm",                         // 24-hour
    ]

    public static func parse(
        _ string: String,
        on reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let cleaned = string.trimmingCharacters(in: .whitespaces)
        let candidates = [cleaned, cleaned.uppercased(), cleaned.lowercased()]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar

        for format in formats {
            formatter.dateFormat = format
            for candidate in candidates {
                guard let parsed = formatter.date(from: candidate) else { continue }
                // Round-trip guard: DateFormatter silently "fixes up" out-of-range
                // input (e.g. "13pm" -> 1:00, "24:00" -> 00:00). Re-render the
                // parsed value and require it to match the input, so garbage is
                // rejected rather than producing a wrong time.
                guard formatter.string(from: parsed).lowercased() == candidate.lowercased() else { continue }
                let comps = calendar.dateComponents([.hour, .minute], from: parsed)
                return calendar.date(
                    bySettingHour: comps.hour ?? 0,
                    minute: comps.minute ?? 0,
                    second: 0,
                    of: reference
                )
            }
        }
        return nil
    }
}
