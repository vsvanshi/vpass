import Foundation
import XCTest
@testable import VPassApp

final class SyncedTOTPRecordTests: XCTestCase {
    func testSyncedRecordContainsOnlyTOTPViewerFields() throws {
        let record = CredentialRecord(
            tag: VaultTag.work.name,
            groupName: "Cloud",
            title: "Hetzner",
            username: "varun@example.com",
            password: "do-not-sync",
            url: "https://example.com",
            notes: "local note",
            customFields: [CustomField(key: "api", value: "secret-token")],
            totpSecretBase32: "JBSWY3DPEHPK3PXP",
            totpIssuer: "Hetzner",
            totpAccount: "varun@example.com",
            totpPeriod: 30,
            totpDigits: 6
        )

        let syncedRecord = try XCTUnwrap(SyncedTOTPRecord(record))
        let data = try JSONEncoder().encode(syncedRecord)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(syncedRecord.title, "Hetzner")
        XCTAssertEqual(syncedRecord.secretBase32, "JBSWY3DPEHPK3PXP")
        XCTAssertFalse(json.contains("do-not-sync"))
        XCTAssertFalse(json.contains("secret-token"))
        XCTAssertFalse(json.contains("local note"))
        XCTAssertFalse(json.contains("https://example.com"))
    }

    func testSyncedRecordRequiresTOTPSecret() {
        let record = CredentialRecord(title: "No MFA", username: "varun@example.com", password: "local")

        XCTAssertNil(SyncedTOTPRecord(record))
    }
}
