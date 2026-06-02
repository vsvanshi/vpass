import Foundation
import Security

enum TOTPKeychainReaderError: LocalizedError {
    case keychain(OSStatus)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain read failed with status \(status)."
        case .decodingFailed:
            return "Could not read the synced authenticator data."
        }
    }
}

final class TOTPKeychainReader {
    private let service = "com.varunsuryawanshi.vpass.totp-sync"
    private let accessGroup = "X937FCYW2Y.com.varunsuryawanshi.vpass.shared"
    private let decoder = JSONDecoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadRecords() throws -> [SyncedTOTPRecord] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        #if targetEnvironment(simulator)
        query.removeValue(forKey: kSecAttrAccessGroup as String)
        #endif

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw TOTPKeychainReaderError.keychain(status)
        }

        let items: [[String: Any]]
        if let item = result as? [String: Any] {
            items = [item]
        } else {
            items = result as? [[String: Any]] ?? []
        }

        let records = try items.compactMap { item -> SyncedTOTPRecord? in
            guard let data = item[kSecValueData as String] as? Data else {
                return nil
            }
            return try decoder.decode(SyncedTOTPRecord.self, from: data)
        }

        return records.sorted {
            if $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedSame {
                if $0.displayGroup.localizedCaseInsensitiveCompare($1.displayGroup) == .orderedSame {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.displayGroup.localizedCaseInsensitiveCompare($1.displayGroup) == .orderedAscending
            }
            return $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending
        }
    }
}
