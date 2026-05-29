import Testing
import Foundation
@testable import NotchCore

@Suite struct ValidationTests {
    @Test func acceptsNormalText() throws {
        #expect(try Validation.validatePoint("Raise the budget question") == "Raise the budget question")
    }

    @Test func trimsWhitespace() throws {
        #expect(try Validation.validatePoint("  ask about Q3   ") == "ask about Q3")
    }

    @Test func rejectsEmptyAfterSanitize() {
        #expect(throws: ValidationError.emptyPoint) {
            try Validation.validatePoint("   ")
        }
    }

    @Test func rejectsOverLength() {
        let long = String(repeating: "x", count: Limits.maxPointLength + 1)
        #expect(throws: ValidationError.pointTooLong(max: Limits.maxPointLength)) {
            try Validation.validatePoint(long)
        }
    }

    @Test func stripsRightToLeftOverride() throws {
        // U+202E is a directionality override used for read-aloud spoofing (origin R18).
        let clean = try Validation.validatePoint("approve\u{202E}contract")
        #expect(!clean.unicodeScalars.contains { $0 == "\u{202E}" })
        #expect(clean == "approvecontract")
    }

    @Test func stripsControlAndNewlines() throws {
        let clean = try Validation.validatePoint("line one\nline\u{0007} two")
        #expect(!clean.contains("\n"))
        #expect(!clean.unicodeScalars.contains { $0 == "\u{0007}" })
    }

    @Test func jsonLikeTextStoredAsLiteral() throws {
        let payload = #"{"checked": true}"#
        #expect(try Validation.validatePoint(payload) == payload)
    }
}
