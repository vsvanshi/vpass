import Foundation
import Security

enum VaultKeychainStoreError: LocalizedError {
    case keychain(OSStatus)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain operation failed with status \(status)."
        case .encodingFailed:
            return "Could not encode the credential."
        case .decodingFailed:
            return "Could not decode synced credentials."
        }
    }
}

final class VaultKeychainStore {
    private let service = "com.varunsuryawanshi.vpass.shared-vault"
    private let deletionService = "com.varunsuryawanshi.vpass.shared-vault.deleted"
    private let accessGroup = "X937FCYW2Y.com.varunsuryawanshi.vpass.shared"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadRecords() throws -> [CredentialRecord] {
        let deletionMarkers = try loadDeletionMarkers()
        var query = baseQuery(service: service)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw VaultKeychainStoreError.keychain(status)
        }

        let records: [CredentialRecord]
        if let data = result as? Data {
            records = [try decoder.decode(CredentialRecord.self, from: data)]
        } else if let dataItems = result as? [Data] {
            records = try dataItems.map { try decoder.decode(CredentialRecord.self, from: $0) }
        } else {
            throw VaultKeychainStoreError.decodingFailed
        }

        let visibleRecords = records.filter { record in
            guard let deletedAt = deletionMarkers[record.id.uuidString] else {
                return true
            }
            if deletedAt >= record.updatedAt {
                try? deleteCredentialItem(id: record.id)
                return false
            }
            return true
        }

        return visibleRecords.sorted {
            if $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedSame {
                if $0.displayGroup.localizedCaseInsensitiveCompare($1.displayGroup) == .orderedSame {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.displayGroup.localizedCaseInsensitiveCompare($1.displayGroup) == .orderedAscending
            }
            return $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending
        }
    }

    func save(_ record: CredentialRecord) throws {
        guard let data = try? encoder.encode(record) else {
            throw VaultKeychainStoreError.encodingFailed
        }

        var query = itemQuery(account: record.id.uuidString, synchronizable: kSecAttrSynchronizableAny)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query = itemQuery(account: record.id.uuidString, synchronizable: true)
            attributes.forEach { query[$0.key] = $0.value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw VaultKeychainStoreError.keychain(addStatus)
            }
            try deleteDeletionMarker(id: record.id)
            return
        }

        guard updateStatus == errSecSuccess else {
            throw VaultKeychainStoreError.keychain(updateStatus)
        }

        try deleteDeletionMarker(id: record.id)
    }

    func delete(id: UUID) throws {
        try saveDeletionMarker(id: id, deletedAt: Date())
        let status = SecItemDelete(itemQuery(account: id.uuidString, synchronizable: kSecAttrSynchronizableAny) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultKeychainStoreError.keychain(status)
        }
    }

    private func itemQuery(account: String, synchronizable: Any) -> [String: Any] {
        var query = baseQuery(service: service)
        query[kSecAttrAccount as String] = account
        query[kSecAttrSynchronizable as String] = synchronizable
        return query
    }

    private func deletionItemQuery(account: String, synchronizable: Any) -> [String: Any] {
        var query = baseQuery(service: deletionService)
        query[kSecAttrAccount as String] = account
        query[kSecAttrSynchronizable as String] = synchronizable
        return query
    }

    private func baseQuery(service: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif
        return query
    }

    private func deleteCredentialItem(id: UUID) throws {
        let status = SecItemDelete(itemQuery(account: id.uuidString, synchronizable: kSecAttrSynchronizableAny) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultKeychainStoreError.keychain(status)
        }
    }

    private func saveDeletionMarker(id: UUID, deletedAt: Date) throws {
        guard let data = try? encoder.encode(DeletionMarker(deletedAt: deletedAt)) else {
            throw VaultKeychainStoreError.encodingFailed
        }

        var query = deletionItemQuery(account: id.uuidString, synchronizable: kSecAttrSynchronizableAny)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query = deletionItemQuery(account: id.uuidString, synchronizable: true)
            attributes.forEach { query[$0.key] = $0.value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw VaultKeychainStoreError.keychain(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw VaultKeychainStoreError.keychain(updateStatus)
        }
    }

    private func deleteDeletionMarker(id: UUID) throws {
        let status = SecItemDelete(deletionItemQuery(account: id.uuidString, synchronizable: kSecAttrSynchronizableAny) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultKeychainStoreError.keychain(status)
        }
    }

    private func loadDeletionMarkers() throws -> [String: Date] {
        var query = baseQuery(service: deletionService)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return [:]
        }
        guard status == errSecSuccess else {
            throw VaultKeychainStoreError.keychain(status)
        }

        let items: [[String: Any]]
        if let item = result as? [String: Any] {
            items = [item]
        } else {
            items = result as? [[String: Any]] ?? []
        }

        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  let marker = try? loadDeletionMarker(account: account) else {
                return nil
            }
            return (account, marker.deletedAt)
        })
    }

    private func loadDeletionMarker(account: String) throws -> DeletionMarker {
        var query = deletionItemQuery(account: account, synchronizable: kSecAttrSynchronizableAny)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            throw VaultKeychainStoreError.decodingFailed
        }
        guard status == errSecSuccess else {
            throw VaultKeychainStoreError.keychain(status)
        }
        guard let data = result as? Data, let marker = try? decoder.decode(DeletionMarker.self, from: data) else {
            throw VaultKeychainStoreError.decodingFailed
        }
        return marker
    }
}

private struct DeletionMarker: Codable {
    let deletedAt: Date
}
