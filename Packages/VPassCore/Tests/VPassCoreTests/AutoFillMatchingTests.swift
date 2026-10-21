import XCTest
import VPassCore

final class AutoFillMatchingTests: XCTestCase {
    func testHostAcceptsValuesWithAndWithoutScheme() {
        XCTAssertEqual(AutoFillDomain.host(from: "example.com"), "example.com")
        XCTAssertEqual(AutoFillDomain.host(from: "https://Login.Example.com/sign-in?x=1"), "login.example.com")
        XCTAssertEqual(AutoFillDomain.host(from: "  www.example.com  "), "example.com")
        XCTAssertEqual(AutoFillDomain.host(from: "http://localhost:8000/login"), "localhost")
        XCTAssertNil(AutoFillDomain.host(from: ""))
        XCTAssertNil(AutoFillDomain.host(from: "   "))
    }

    func testMatchesSameSiteAndSubdomains() {
        XCTAssertTrue(AutoFillDomain.matches("example.com", "example.com"))
        XCTAssertTrue(AutoFillDomain.matches("example.com", "login.example.com"))
        XCTAssertTrue(AutoFillDomain.matches("accounts.example.com", "example.com"))
        XCTAssertFalse(AutoFillDomain.matches("example.com", "notexample.com"))
        XCTAssertFalse(AutoFillDomain.matches("example.com", "example.org"))
    }

    func testDotlessHostsOnlyMatchExactly() {
        XCTAssertTrue(AutoFillDomain.matches("localhost", "localhost"))
        XCTAssertFalse(AutoFillDomain.matches("com", "example.com"))
    }

    func testRecordMatchesServiceIdentifier() {
        let record = CredentialRecord(title: "GitHub", username: "varun", url: "github.com")

        XCTAssertEqual(record.autofillDomain, "github.com")
        XCTAssertTrue(record.matchesAutofillService("https://github.com/login"))
        XCTAssertTrue(record.matchesAutofillService("gist.github.com"))
        XCTAssertFalse(record.matchesAutofillService("https://gitlab.com"))
        XCTAssertFalse(CredentialRecord(title: "No site").matchesAutofillService("github.com"))
    }

    func testLabelsLeadWithNameWhenUsernameIsShared() {
        let stage = CredentialRecord(title: "Stage Platform", username: "varun@infinx.com", url: "stageplatform.infinx.com")
        let review = CredentialRecord(title: "Auth Review AI", username: "Varun@infinx.com", url: "authreviewai.infinx.com")
        let github = CredentialRecord(title: "GitHub", username: "vsvanshi", url: "github.com")

        let labels = CredentialRecord.autofillLabels(for: [stage, review, github])

        XCTAssertEqual(labels[stage.id], "Stage Platform - varun@infinx.com")
        XCTAssertEqual(labels[review.id], "Auth Review AI - Varun@infinx.com")
        XCTAssertEqual(labels[github.id], "vsvanshi")
    }

    func testLabelsSkipNameWhenItAddsNothing() {
        let untitled = CredentialRecord(title: " ", username: "shared", url: "a.example.com")
        let sameAsUser = CredentialRecord(title: "shared", username: "shared", url: "b.example.com")

        let labels = CredentialRecord.autofillLabels(for: [untitled, sameAsUser])

        XCTAssertEqual(labels[untitled.id], "shared")
        XCTAssertEqual(labels[sameAsUser.id], "shared")
    }

    func testAutofillUserFallsBackToTitle() {
        XCTAssertEqual(CredentialRecord(title: "Bank", username: "varun").autofillUser, "varun")
        XCTAssertEqual(CredentialRecord(title: "Bank", username: " ").autofillUser, "Bank")
    }
}
