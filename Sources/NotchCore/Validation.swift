import Foundation

/// Write-time limits (origin R16). Enforced by the CLI/service so the list
/// stays bounded to what the notch can display.
public enum Limits {
    public static let maxPointsPerEntry = 7
    public static let maxPointLength = 80
    /// A meeting title is a single glanceable header, so it is capped shorter
    /// than a point.
    public static let maxTitleLength = 60
}

public enum ValidationError: Error, Equatable, CustomStringConvertible {
    case emptyPoint
    case pointTooLong(max: Int)
    case tooManyPoints(max: Int)
    case titleTooLong(max: Int)

    public var description: String {
        switch self {
        case .emptyPoint:
            return "point text is empty after sanitization"
        case .pointTooLong(let max):
            return "point text exceeds \(max) characters"
        case .tooManyPoints(let max):
            return "an entry may hold at most \(max) points"
        case .titleTooLong(let max):
            return "title exceeds \(max) characters"
        }
    }
}

/// Treats all point text as untrusted input (origin R18). Strips Unicode
/// control (Cc), format (Cf — including the RLO/LRO/PDF directionality
/// overrides used for read-aloud spoofing), surrogate (Cs), private-use, and
/// unassigned scalars, then normalizes to NFC and trims surrounding
/// whitespace. Text is stored and rendered as inert data, never interpolated.
public enum Sanitizer {
    public static func sanitize(_ raw: String) -> String {
        let kept = raw.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator:
                return false
            default:
                return true
            }
        }
        let collapsed = String(String.UnicodeScalarView(kept))
        return collapsed
            .precomposedStringWithCanonicalMapping // NFC
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum Validation {
    /// Sanitize and validate a single point's text, returning the cleaned
    /// value or throwing. Length is measured after sanitization.
    public static func validatePoint(_ raw: String) throws -> String {
        let clean = Sanitizer.sanitize(raw)
        if clean.isEmpty { throw ValidationError.emptyPoint }
        if clean.count > Limits.maxPointLength {
            throw ValidationError.pointTooLong(max: Limits.maxPointLength)
        }
        return clean
    }

    /// Sanitize and validate a meeting title. Unlike a point, an empty title is
    /// allowed and means "clear it" — returning `nil`. Length is measured after
    /// sanitization; exactly `maxTitleLength` is accepted, one more throws.
    public static func validateTitle(_ raw: String) throws -> String? {
        let clean = Sanitizer.sanitize(raw)
        if clean.isEmpty { return nil }
        if clean.count > Limits.maxTitleLength {
            throw ValidationError.titleTooLong(max: Limits.maxTitleLength)
        }
        return clean
    }
}
