import Foundation
import Security

enum BackupConfigurationError: LocalizedError {
    case missingPassword
    case invalidPasswordData
    case missingDestination
    case staleBookmark
    case bookmarkCreationFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            return "The automatic backup password was not found in Keychain."
        case .invalidPasswordData:
            return "The automatic backup password could not be read from Keychain."
        case .missingDestination:
            return "The automatic backup file could not be found."
        case .staleBookmark:
            return "The automatic backup location needs to be selected again."
        case .bookmarkCreationFailed:
            return "The automatic backup location could not be saved."
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

    var displayName: String {
        url.lastPathComponent.isEmpty ? "Backup file" : url.lastPathComponent
    }
}

final class BackupConfigurationStore {
    private let bookmarkDefaultsKey = "automaticBackupBookmark"
    private let keychainService = "com.varun.vpass.automatic-backup"
    private let keychainAccount = "backup-master-password"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasDestination: Bool {
        userDefaults.data(forKey: bookmarkDefaultsKey) != nil
    }

    func isConfigured() -> Bool {
        hasDestination && ((try? loadPassword())?.isEmpty == false)
    }

    func saveConfiguration(url: URL, password: String) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        guard !bookmarkData.isEmpty else {
            throw BackupConfigurationError.bookmarkCreationFailed
        }

        try savePassword(password)
        userDefaults.set(bookmarkData, forKey: bookmarkDefaultsKey)
    }

    func loadDestination() throws -> BackupDestination {
        guard let bookmarkData = userDefaults.data(forKey: bookmarkDefaultsKey) else {
            throw BackupConfigurationError.missingDestination
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else {
            throw BackupConfigurationError.staleBookmark
        }
        return BackupDestination(url: url)
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
        userDefaults.removeObject(forKey: bookmarkDefaultsKey)
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BackupConfigurationError.keychain(status)
        }
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

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }
}
