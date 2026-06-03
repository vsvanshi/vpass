import Foundation
import LocalAuthentication
import Security

enum BackupConfigurationError: LocalizedError {
    case missingPassword
    case invalidPasswordData
    case missingBackupDirectory
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            return "The automatic backup password was not found in Keychain."
        case .invalidPasswordData:
            return "The automatic backup password could not be read from Keychain."
        case .missingBackupDirectory:
            return "The automatic backup folder could not be created."
        case .keychain(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain operation failed with status \(status)."
        }
    }
}

struct BackupDestination: Equatable {
    let url: URL
    let previousURL: URL

    var displayName: String {
        url.lastPathComponent.isEmpty ? "Backup file" : url.lastPathComponent
    }
}

struct BackupFileInfo: Equatable {
    let url: URL
    let modifiedAt: Date?
    let size: Int64

    var exists: Bool {
        modifiedAt != nil
    }
}

final class BackupConfigurationStore {
    private let legacyBookmarkDefaultsKey = "automaticBackupBookmark"
    private let dataProtectionMigratedKey = "com.varun.vpass.automatic-backup.dataProtectionMigrated"
    private let keychainService = "com.varun.vpass.automatic-backup"
    private let keychainAccount = "backup-master-password"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        migrateToDataProtectionKeychainIfNeeded()
    }

    func isConfigured() -> Bool {
        (try? loadPassword())?.isEmpty == false
    }

    func saveConfiguration(password: String) throws {
        try savePassword(password)
        userDefaults.removeObject(forKey: legacyBookmarkDefaultsKey)
    }

    func loadDestination() throws -> BackupDestination {
        let directory = try automaticBackupDirectory()
        return BackupDestination(
            url: directory.appendingPathComponent("VPass.vpassbackup"),
            previousURL: directory.appendingPathComponent("VPass.previous.vpassbackup")
        )
    }

    func backupFileInfo(for url: URL) -> BackupFileInfo {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes?[.modificationDate] as? Date
        let size = attributes?[.size] as? NSNumber
        return BackupFileInfo(url: url, modifiedAt: modifiedAt, size: size?.int64Value ?? 0)
    }

    func loadPassword() throws -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            throw BackupConfigurationError.missingPassword
        }
        guard status == errSecSuccess else {
            throw BackupConfigurationError.keychain(status)
        }
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw BackupConfigurationError.invalidPasswordData
        }
        return password
    }

    func clear() throws {
        userDefaults.removeObject(forKey: legacyBookmarkDefaultsKey)
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BackupConfigurationError.keychain(status)
        }
    }

    private func automaticBackupDirectory() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appFolder = applicationSupportURL.appendingPathComponent("VPass", isDirectory: true)
        let backupFolder = appFolder.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: backupFolder.path) else {
            throw BackupConfigurationError.missingBackupDirectory
        }
        return backupFolder
    }

    private func savePassword(_ password: String) throws {
        guard let data = password.data(using: .utf8), !password.isEmpty else {
            throw BackupConfigurationError.missingPassword
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var query = baseQuery()
            attributes.forEach { query[$0.key] = $0.value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw BackupConfigurationError.keychain(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw BackupConfigurationError.keychain(updateStatus)
        }
    }

    private func baseQuery(dataProtection: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        if dataProtection {
            // Store in the data protection keychain so reads aren't gated by a
            // signature-bound ACL in the file-based "login" keychain, which
            // re-prompts on every dev rebuild. See KeychainVault.baseQuery.
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private func migrateToDataProtectionKeychainIfNeeded() {
        guard !userDefaults.bool(forKey: dataProtectionMigratedKey) else {
            return
        }
        defer { userDefaults.set(true, forKey: dataProtectionMigratedKey) }

        // Already in the data protection keychain? Nothing to migrate.
        if (try? loadPassword())?.isEmpty == false {
            return
        }

        // Read any password left in the file-based keychain WITHOUT prompting,
        // and re-save it into the data protection keychain.
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery(dataProtection: false)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8),
              !password.isEmpty else {
            return
        }
        try? savePassword(password)
    }
}
