import Foundation
import Security

enum VaultError: LocalizedError {
    case keychain(OSStatus)
    case missingRecord
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain operation failed with status \(status)."
        case .missingRecord:
            return "The saved item could not be found."
        case .encodingFailed:
            return "Could not encode the vault item."
        case .decodingFailed:
            return "Could not decode the vault item."
        }
    }
}

final class KeychainVault {
    private let service = "com.varun.vpass.vault"
    private let indexKey = "com.varun.vpass.vault.index"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadRecords() throws -> [CredentialRecord] {
        try loadIDs().compactMap { id in
            try? loadRecord(id: id)
        }.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func save(_ record: CredentialRecord) throws {
        guard let data = try? encoder.encode(record) else {
            throw VaultError.encodingFailed
        }

        var query = baseQuery(account: record.id.uuidString)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            attributes.forEach { query[$0.key] = $0.value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw VaultError.keychain(addStatus)
            }
            appendID(record.id)
            return
        }

        guard updateStatus == errSecSuccess else {
            throw VaultError.keychain(updateStatus)
        }
        appendID(record.id)
    }

    func delete(id: UUID) throws {
        let status = SecItemDelete(baseQuery(account: id.uuidString) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychain(status)
        }
        removeID(id)
    }

    private func loadRecord(id: UUID) throws -> CredentialRecord {
        var query = baseQuery(account: id.uuidString)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            throw VaultError.missingRecord
        }
        guard status == errSecSuccess else {
            throw VaultError.keychain(status)
        }
        guard let data = result as? Data, let record = try? decoder.decode(CredentialRecord.self, from: data) else {
            throw VaultError.decodingFailed
        }
        return record
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func loadIDs() throws -> [UUID] {
        guard let strings = userDefaults.stringArray(forKey: indexKey) else {
            return []
        }
        return strings.compactMap(UUID.init(uuidString:))
    }

    private func saveIDs(_ ids: [UUID]) {
        userDefaults.set(ids.map(\.uuidString), forKey: indexKey)
    }

    private func appendID(_ id: UUID) {
        var ids = (try? loadIDs()) ?? []
        if !ids.contains(id) {
            ids.append(id)
            saveIDs(ids)
        }
    }

    private func removeID(_ id: UUID) {
        let ids = ((try? loadIDs()) ?? []).filter { $0 != id }
        saveIDs(ids)
    }
}
