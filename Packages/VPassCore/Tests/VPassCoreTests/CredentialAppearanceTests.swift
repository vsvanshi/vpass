import XCTest
import VPassCore

final class CredentialAppearanceTests: XCTestCase {
    func testMonogramUsesFirstLetterOrDigit() {
        XCTAssertEqual(CredentialRecord(title: "medical Necessity").monogram, "M")
        XCTAssertEqual(CredentialRecord(title: "  (prod) Infinx").monogram, "P")
        XCTAssertEqual(CredentialRecord(title: "3M Portal").monogram, "3")
        XCTAssertEqual(CredentialRecord(title: "", username: "varun").monogram, "V")
        XCTAssertEqual(CredentialRecord(title: "", username: "").monogram, "?")
    }

    func testColorIsStablePerSite() {
        let palette = 10
        let first = CredentialRecord(title: "A", url: "https://github.com/login")
        let second = CredentialRecord(title: "B", url: "github.com")
        XCTAssertEqual(first.monogramColorIndex(paletteCount: palette), second.monogramColorIndex(paletteCount: palette))
        XCTAssertTrue((0..<palette).contains(first.monogramColorIndex(paletteCount: palette)))
        // Pinned (FNV-1a of "github.com" mod 10, computed independently) so a
        // site's color never changes between releases.
        XCTAssertEqual(first.monogramColorIndex(paletteCount: palette), 9)
    }

    func testColorFallsBackToNameWithoutSite() {
        let record = CredentialRecord(title: "Bank")
        XCTAssertEqual(record.monogramColorIndex(paletteCount: 7), CredentialRecord(title: " bank ").monogramColorIndex(paletteCount: 7))
        XCTAssertEqual(record.monogramColorIndex(paletteCount: 0), 0)
    }

    func testGroupedCode() {
        XCTAssertEqual(TOTPGenerator.grouped("123456"), "123 456")
        XCTAssertEqual(TOTPGenerator.grouped("12345678"), "1234 5678")
        XCTAssertEqual(TOTPGenerator.grouped("1234567"), "1234 567")
        XCTAssertEqual(TOTPGenerator.grouped("12345"), "12345")
    }
}
