import Foundation
import XCTest
@testable import VPassApp

final class KeychainVaultTests: XCTestCase {
    func testSaveLoadDeleteCredential() throws {
        let suiteName = "VPassAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let vault = KeychainVault(userDefaults: defaults)
        let record = CredentialRecord(
            id: UUID(),
            tag: VaultTag.work.name,
            groupName: "ContractIQ App",
            title: "ContractIQ Admin",
            username: "admin@example.com",
            password: "test-password",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        defer {
            try? vault.delete(id: record.id)
        }

        try vault.save(record)
        let loaded = try XCTUnwrap(vault.loadRecords().first { $0.id == record.id })
        XCTAssertEqual(loaded.tag, VaultTag.work.name)
        XCTAssertEqual(loaded.groupName, "ContractIQ App")
        XCTAssertEqual(loaded.password, "test-password")
        XCTAssertEqual(loaded.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))

        try vault.delete(id: record.id)
        XCTAssertFalse(try vault.loadRecords().contains { $0.id == record.id })
    }
}
