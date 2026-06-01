import Foundation
import XCTest
@testable import VPassApp

final class BackupServiceTests: XCTestCase {
    func testEncryptedBackupRoundTrip() throws {
        let service = BackupService()
        let records = [
            CredentialRecord(
                tag: VaultTag.personal.name,
                groupName: "Recovery",
                title: "Hetzner",
                username: "varun@example.com",
                password: "secret-password",
                notes: "Recovery note",
                totpSecretBase32: "JBSWY3DPEHPK3PXP",
                totpIssuer: "Hetzner",
                totpAccount: "varun@example.com"
            )
        ]

        let backup = try service.export(records: records, password: "backup-password")
        let restored = try service.import(data: backup, password: "backup-password")

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, records.first?.id)
        XCTAssertEqual(restored.first?.title, "Hetzner")
        XCTAssertEqual(restored.first?.password, "secret-password")
        XCTAssertEqual(restored.first?.totpSecretBase32, "JBSWY3DPEHPK3PXP")
        XCTAssertFalse(String(data: backup, encoding: .utf8)?.contains("secret-password") ?? true)
        XCTAssertFalse(String(data: backup, encoding: .utf8)?.contains("JBSWY3DPEHPK3PXP") ?? true)
    }

    func testWrongPasswordFails() throws {
        let service = BackupService()
        let backup = try service.export(
            records: [CredentialRecord(title: "Example", password: "secret")],
            password: "backup-password"
        )

        XCTAssertThrowsError(try service.import(data: backup, password: "wrong-password")) { error in
            XCTAssertEqual(error.localizedDescription, BackupError.decryptionFailed.localizedDescription)
        }
    }
}
