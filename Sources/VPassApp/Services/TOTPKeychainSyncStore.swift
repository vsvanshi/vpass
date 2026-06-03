import Foundation
import Security

enum TOTPKeychainSyncError: LocalizedError {
    case encodingFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode the TOTP sync item."
        case .keychain(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "TOTP sync failed with Keychain status \(status)."
        }
    }
}

final class TOTPKeychainSyncStore {
    static let sharedAccessGroupIdentifier = "com.varunsuryawanshi.vpass.shared"

    private let service = "com.varunsuryawanshi.vpass.totp-sync"
    private let encoder = JSONEncoder()
    private let accessGroup: String?

    init(accessGroup: String? = TOTPKeychainSyncStore.defaultAccessGroup()) {
        self.accessGroup = accessGroup
        encoder.dateEncodingStrategy = .iso8601
    }

    func sync(records: [CredentialRecord]) throws {
        guard accessGroup != nil else {
            return
        }
        let syncedRecords = records.compactMap(SyncedTOTPRecord.init)
        let expectedIDs = Set(syncedRecords.map(\.id.uuidString))
        let existingIDs = try loadSyncedIDs()

        for record in syncedRecords {
            try save(record)
        }

        for staleID in existingIDs.subtracting(expectedIDs) {
            try delete(account: staleID)
        }
    }

    func clear() throws {
        guard accessGroup != nil else {
            return
        }
        let status = SecItemDelete(allItemsQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TOTPKeychainSyncError.keychain(status)
        }
    }

    private func save(_ record: SyncedTOTPRecord) throws {
        guard let data = try? encoder.encode(record) else {
            throw TOTPKeychainSyncError.encodingFailed
        }

        let account = record.id.uuidString
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true
        ]

        var query = itemQuery(account: account, synchronizable: kSecAttrSynchronizableAny)
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query = itemQuery(account: account, synchronizable: true)
            attributes.forEach { query[$0.key] = $0.value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TOTPKeychainSyncError.keychain(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw TOTPKeychainSyncError.keychain(updateStatus)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(itemQuery(account: account, synchronizable: kSecAttrSynchronizableAny) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TOTPKeychainSyncError.keychain(status)
        }
    }

    private func loadSyncedIDs() throws -> Set<String> {
        var query = allItemsQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw TOTPKeychainSyncError.keychain(status)
        }

        if let item = result as? [String: Any],
           let account = item[kSecAttrAccount as String] as? String {
            return [account]
        }

        let items = result as? [[String: Any]] ?? []
        return Set(items.compactMap { $0[kSecAttrAccount as String] as? String })
    }

    private func allItemsQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        return query
    }

    private func itemQuery(account: String, synchronizable: Any) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrAccount as String] = account
        query[kSecAttrSynchronizable as String] = synchronizable
        return query
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func defaultAccessGroup() -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return nil
        }

        if let groups = SecTaskCopyValueForEntitlement(
            task,
            "keychain-access-groups" as CFString,
            nil
        ) as? [String],
           let sharedGroup = groups.first(where: { $0.hasSuffix(".\(sharedAccessGroupIdentifier)") }) {
            return sharedGroup
        }

        return nil
    }
}
