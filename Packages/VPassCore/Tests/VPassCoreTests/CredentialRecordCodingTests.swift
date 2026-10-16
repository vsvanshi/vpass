import Foundation
import XCTest
import VPassCore

final class CredentialRecordCodingTests: XCTestCase {
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func testRoundTripPreservesAllFields() throws {
        let record = CredentialRecord(
            tag: VaultTag.servers.name,
            groupName: "Hetzner",
            title: "Stage box",
            username: "root",
            password: "pw",
            url: "https://example.com",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            notes: "note",
            customFields: [CustomField(key: "api", value: "token", isSensitive: true)],
            totpSecretBase32: "JBSWY3DPEHPK3PXP",
            totpIssuer: "Hetzner",
            totpAccount: "root",
            totpPeriod: 30,
            totpDigits: 6,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let decoded = try makeDecoder().decode(CredentialRecord.self, from: makeEncoder().encode(record))

        XCTAssertEqual(decoded, record)
    }

    func testDecodesRecordsSavedBeforeTagsAndGroups() throws {
        let json = """
        {
          "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "title": "Old record",
          "username": "varun",
          "password": "pw",
          "url": "",
          "notes": "",
          "customFields": [],
          "totpSecretBase32": "",
          "totpIssuer": "",
          "totpAccount": "",
          "totpPeriod": 30,
          "totpDigits": 6,
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """

        let record = try makeDecoder().decode(CredentialRecord.self, from: Data(json.utf8))

        XCTAssertEqual(record.tag, VaultTag.personal.name)
        XCTAssertEqual(record.groupName, "General")
        XCTAssertNil(record.expiresAt)
    }

    func testDisplayGroupFallsBackToGeneral() {
        XCTAssertEqual(CredentialRecord(groupName: "  ").displayGroup, "General")
        XCTAssertEqual(CredentialRecord(groupName: "Cloud").displayGroup, "Cloud")
    }

    func testHasTOTPIgnoresWhitespaceOnlySecret() {
        XCTAssertFalse(CredentialRecord(totpSecretBase32: "  ").hasTOTP)
        XCTAssertTrue(CredentialRecord(totpSecretBase32: "JBSWY3DPEHPK3PXP").hasTOTP)
    }
}
