import Foundation
import LocalAuthentication
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
    private let service: String
    private let deletionService: String
    private let legacyService = "com.varun.vpass.vault"
    private let legacyIndexKey = "com.varun.vpass.vault.index"
    private let migrationKey = "com.varunsuryawanshi.vpass.shared-vault.migrated"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let accessGroup: String?
    private let synchronizesWithiCloud: Bool
    private let usesDataProtectionKeychain: Bool
    private var canUseSharedCloudVault: Bool {
        synchronizesWithiCloud && accessGroup != nil
    }

    var isCloudSyncAvailable: Bool {
        canUseSharedCloudVault
    }

    init(
        userDefaults: UserDefaults = .standard,
        accessGroup: String? = KeychainVault.defaultAccessGroup(),
        synchronizesWithiCloud: Bool = true,
        service: String = "com.varunsuryawanshi.vpass.shared-vault",
        deletionService: String = "com.varunsuryawanshi.vpass.shared-vault.deleted",
        // The data protection keychain requires the process to be signed with
        // the keychain-access-groups / app-identifier entitlement. The real
        // app has it; an unsigned unit-test binary does not, so tests inject
        // `false` to exercise the file-based keychain instead.
        usesDataProtectionKeychain: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.accessGroup = accessGroup
        self.synchronizesWithiCloud = synchronizesWithiCloud && accessGroup != nil
        self.service = service
        self.deletionService = deletionService
        self.usesDataProtectionKeychain = usesDataProtectionKeychain
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadRecords() throws -> [CredentialRecord] {
        migrateToDataProtectionKeychainIfNeeded()
        try migrateLegacyRecordsIfNeeded()
        return try loadSharedRecords().sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func save(_ record: CredentialRecord) throws {
        guard let data = try? encoder.encode(record) else {
            throw VaultError.encodingFailed
        }

        var query = sharedItemQuery(account: record.id.uuidString, synchronizable: kSecAttrSynchronizableAny)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        var writeAttributes = attributes
        if canUseSharedCloudVault {
            writeAttributes[kSecAttrSynchronizable as String] = true
        }

        let updateStatus = SecItemUpdate(query as CFDictionary, writeAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query = sharedItemQuery(account: record.id.uuidString, synchronizable: canUseSharedCloudVault ? true : nil)
            writeAttributes.forEach { query[$0.key] = $0.value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw VaultError.keychain(addStatus)
            }
            if canUseSharedCloudVault {
                try deleteDeletionMarker(id: record.id)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw VaultError.keychain(updateStatus)
        }

        if canUseSharedCloudVault {
            try deleteDeletionMarker(id: record.id)
        }
    }

    func delete(id: UUID) throws {
        if canUseSharedCloudVault {
            try saveDeletionMarker(id: id, deletedAt: Date())
        }
        let status = SecItemDelete(sharedItemQuery(account: id.uuidString, synchronizable: kSecAttrSynchronizableAny) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychain(status)
        }
    }

    func loadLocalOnlyRecordsForRecovery() throws -> [CredentialRecord] {
        try loadLocalVaultRecords(allowsAuthentication: true)
    }

    private func loadSharedRecords() throws -> [CredentialRecord] {
        let deletionMarkers = try loadDeletionMarkers()
        let records = try loadSharedAccounts().compactMap { account in
            try? loadSharedRecord(account: account)
        }
        return records.filter { record in
            guard let deletedAt = deletionMarkers[record.id.uuidString] else {
                return true
            }
            if deletedAt >= record.updatedAt {
                try? deleteRecordItem(id: record.id)
                return false
            }
            return true
        }
    }

    private func loadSharedAccounts() throws -> [String] {
        var query = sharedBaseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        if canUseSharedCloudVault {
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw VaultError.keychain(status)
        }

        if let item = result as? [String: Any],
           let account = item[kSecAttrAccount as String] as? String {
            return [account]
        }

        let items = result as? [[String: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func loadSharedRecord(account: String) throws -> CredentialRecord {
        var query = sharedItemQuery(account: account, synchronizable: kSecAttrSynchronizableAny)
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

    private func sharedItemQuery(account: String, synchronizable: Any?) -> [String: Any] {
        var query = sharedBaseQuery()
        query[kSecAttrAccount as String] = account
        if canUseSharedCloudVault, let synchronizable {
            query[kSecAttrSynchronizable as String] = synchronizable
        }
        return query
    }

    private func deletionItemQuery(account: String, synchronizable: Any?) -> [String: Any] {
        var query = deletionBaseQuery()
        query[kSecAttrAccount as String] = account
        if canUseSharedCloudVault, let synchronizable {
            query[kSecAttrSynchronizable as String] = synchronizable
        }
        return query
    }

    private func sharedBaseQuery() -> [String: Any] {
        baseQuery(service: service)
    }

    private func deletionBaseQuery() -> [String: Any] {
        baseQuery(service: deletionService)
    }

    private func baseQuery(service: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if usesDataProtectionKeychain {
            // Route to the data protection keychain. It is the only macOS
            // keychain that participates in iCloud Keychain sync and shares
            // access groups with the iOS app. Without this flag the SecItem
            // APIs fall back to the legacy file-based "login" keychain, whose
            // items are bound to the app's code signature by an ACL — so every
            // dev rebuild (new signature) triggers the "allow access" prompt,
            // and `kSecAttrSynchronizable` never actually syncs.
            query[kSecUseDataProtectionKeychain as String] = true
        }
        if canUseSharedCloudVault, let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func deleteRecordItem(id: UUID) throws {
        let status = SecItemDelete(sharedItemQuery(account: id.uuidString, synchronizable: kSecAttrSynchronizableAny) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychain(status)
        }
    }

    private func saveDeletionMarker(id: UUID, deletedAt: Date) throws {
        guard let data = try? encoder.encode(DeletionMarker(deletedAt: deletedAt)) else {
            throw VaultError.encodingFailed
        }

        var query = deletionItemQuery(account: id.uuidString, synchronizable: kSecAttrSynchronizableAny)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        var writeAttributes = attributes
        if canUseSharedCloudVault {
            writeAttributes[kSecAttrSynchronizable as String] = true
        }

        let updateStatus = SecItemUpdate(query as CFDictionary, writeAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query = deletionItemQuery(account: id.uuidString, synchronizable: canUseSharedCloudVault ? true : nil)
            writeAttributes.forEach { query[$0.key] = $0.value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw VaultError.keychain(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw VaultError.keychain(updateStatus)
        }
    }

    private func deleteDeletionMarker(id: UUID) throws {
        guard canUseSharedCloudVault else {
            return
        }
        let status = SecItemDelete(deletionItemQuery(account: id.uuidString, synchronizable: kSecAttrSynchronizableAny) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychain(status)
        }
    }

    private func loadDeletionMarkers() throws -> [String: Date] {
        guard canUseSharedCloudVault else {
            return [:]
        }
        var query = deletionBaseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        if canUseSharedCloudVault {
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return [:]
        }
        guard status == errSecSuccess else {
            throw VaultError.keychain(status)
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
            throw VaultError.missingRecord
        }
        guard status == errSecSuccess else {
            throw VaultError.keychain(status)
        }
        guard let data = result as? Data, let marker = try? decoder.decode(DeletionMarker.self, from: data) else {
            throw VaultError.decodingFailed
        }
        return marker
    }

    private func legacyBaseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: nonInteractiveKeychainContext()
        ]
    }

    private func localVaultBaseQuery(allowsAuthentication: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if !allowsAuthentication {
            query[kSecUseAuthenticationContext as String] = nonInteractiveKeychainContext()
        }
        return query
    }

    private func nonInteractiveKeychainContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    private func localVaultItemQuery(account: String, allowsAuthentication: Bool = false) -> [String: Any] {
        var query = localVaultBaseQuery(allowsAuthentication: allowsAuthentication)
        query[kSecAttrAccount as String] = account
        return query
    }

    private func loadCloudRecordsWithoutMigration() throws -> [CredentialRecord] {
        let deletionMarkers = try loadDeletionMarkers()
        let records = try loadSharedAccounts().compactMap { account in
            try? loadSharedRecord(account: account)
        }
        return records.filter { record in
            guard let deletedAt = deletionMarkers[record.id.uuidString] else {
                return true
            }
            return deletedAt < record.updatedAt
        }
    }

    private func loadLocalVaultRecords(allowsAuthentication: Bool = false) throws -> [CredentialRecord] {
        try loadLocalVaultAccounts(allowsAuthentication: allowsAuthentication).compactMap { account in
            try? loadLocalVaultRecord(account: account, allowsAuthentication: allowsAuthentication)
        }
    }

    private func loadLocalVaultAccounts(allowsAuthentication: Bool = false) throws -> [String] {
        var query = localVaultBaseQuery(allowsAuthentication: allowsAuthentication)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw VaultError.keychain(status)
        }

        if let item = result as? [String: Any],
           let account = item[kSecAttrAccount as String] as? String {
            return [account]
        }

        let items = result as? [[String: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func loadLocalVaultRecord(account: String, allowsAuthentication: Bool = false) throws -> CredentialRecord {
        var query = localVaultItemQuery(account: account, allowsAuthentication: allowsAuthentication)
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

    private func migrateToDataProtectionKeychainIfNeeded() {
        let migratedKey = "com.varunsuryawanshi.vpass.shared-vault.dataProtectionMigrated"
        guard !userDefaults.bool(forKey: migratedKey) else {
            return
        }

        // Records written before the data protection keychain fix landed in
        // the file-based "login" keychain. Copy whatever we can read WITHOUT
        // prompting (the local-vault reader uses a non-interactive context)
        // into the data protection keychain so they keep appearing and start
        // syncing. Best-effort: anything unreadable stays put and can still be
        // recovered from an encrypted backup.
        let fileBasedRecords = (try? loadLocalVaultRecords(allowsAuthentication: false)) ?? []
        for record in fileBasedRecords {
            try? save(record)
        }

        userDefaults.set(true, forKey: migratedKey)
    }

    private func migrateLegacyRecordsIfNeeded() throws {
        guard !userDefaults.bool(forKey: migrationKey) else {
            return
        }

        let legacyRecords = try loadLegacyRecords()
        let sharedRecords = try loadSharedRecords()
        var merged = Dictionary(uniqueKeysWithValues: sharedRecords.map { ($0.id, $0) })

        for record in legacyRecords {
            if let existing = merged[record.id], existing.updatedAt >= record.updatedAt {
                continue
            }
            try save(record)
            merged[record.id] = record
        }

        userDefaults.set(true, forKey: migrationKey)
    }

    private func loadLegacyRecords() throws -> [CredentialRecord] {
        try loadLegacyIDs().compactMap { id in
            try? loadLegacyRecord(id: id)
        }
    }

    private func loadLegacyRecord(id: UUID) throws -> CredentialRecord {
        var query = legacyBaseQuery(account: id.uuidString)
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

    private func loadLegacyIDs() throws -> [UUID] {
        guard let strings = userDefaults.stringArray(forKey: legacyIndexKey) else {
            return []
        }
        return strings.compactMap(UUID.init(uuidString:))
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
           let sharedGroup = groups.first(where: { $0.hasSuffix(".com.varunsuryawanshi.vpass.shared") }) {
            return sharedGroup
        }

        return nil
    }
}

private struct DeletionMarker: Codable {
    let deletedAt: Date
}
