import Foundation

struct CredentialRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var tag: String
    var groupName: String
    var title: String
    var username: String
    var password: String
    var url: String
    var expiresAt: Date?
    var notes: String
    var customFields: [CustomField]
    var totpSecretBase32: String
    var totpIssuer: String
    var totpAccount: String
    var totpPeriod: Int
    var totpDigits: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        tag: String = VaultTag.personal.name,
        groupName: String = "General",
        title: String = "",
        username: String = "",
        password: String = "",
        url: String = "",
        expiresAt: Date? = nil,
        notes: String = "",
        customFields: [CustomField] = [],
        totpSecretBase32: String = "",
        totpIssuer: String = "",
        totpAccount: String = "",
        totpPeriod: Int = 30,
        totpDigits: Int = 6,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.tag = tag
        self.groupName = groupName
        self.title = title
        self.username = username
        self.password = password
        self.url = url
        self.expiresAt = expiresAt
        self.notes = notes
        self.customFields = customFields
        self.totpSecretBase32 = totpSecretBase32
        self.totpIssuer = totpIssuer
        self.totpAccount = totpAccount
        self.totpPeriod = totpPeriod
        self.totpDigits = totpDigits
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension CredentialRecord {
    var displayGroup: String {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "General" : groupName
    }

    var hasTOTP: Bool {
        !totpSecretBase32.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matches(_ query: String) -> Bool {
        let tokens = query.searchTokens
        guard !tokens.isEmpty else {
            return true
        }

        let searchableText = [
            title,
            username,
            url,
            tag,
            groupName,
            totpIssuer,
            totpAccount,
            notes
        ]
            .joined(separator: " ")
            .searchNormalized

        return tokens.allSatisfy { searchableText.contains($0) }
    }
}

private extension String {
    var searchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    var searchTokens: [String] {
        searchNormalized
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}

struct VaultTag: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let systemImage: String

    static let personal = VaultTag(name: "Personal", systemImage: "person")
    static let work = VaultTag(name: "Work", systemImage: "briefcase")
    static let finance = VaultTag(name: "Finance", systemImage: "creditcard")
    static let servers = VaultTag(name: "Servers", systemImage: "server.rack")
    static let all: [VaultTag] = [.personal, .work, .finance, .servers]
}

struct CustomField: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var key: String
    var value: String
    var isSensitive: Bool

    init(id: UUID = UUID(), key: String = "", value: String = "", isSensitive: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.isSensitive = isSensitive
    }
}

struct CredentialDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var tag: String
    var groupName: String
    var title: String
    var username: String
    var password: String
    var url: String
    var hasExpiry: Bool
    var expiresAt: Date
    var notes: String
    var customFields: [CustomField]
    var totpSecretBase32: String
    var totpIssuer: String
    var totpAccount: String
    var totpPeriod: Int
    var totpDigits: Int
    var createdAt: Date

    init(record: CredentialRecord? = nil) {
        let record = record ?? CredentialRecord()
        id = record.id
        tag = record.tag
        groupName = record.groupName
        title = record.title
        username = record.username
        password = record.password
        url = record.url
        hasExpiry = record.expiresAt != nil
        expiresAt = record.expiresAt ?? Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        notes = record.notes
        customFields = record.customFields
        totpSecretBase32 = record.totpSecretBase32
        totpIssuer = record.totpIssuer
        totpAccount = record.totpAccount
        totpPeriod = record.totpPeriod
        totpDigits = record.totpDigits
        createdAt = record.createdAt
    }

    func record() -> CredentialRecord {
        CredentialRecord(
            id: id,
            tag: tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? VaultTag.personal.name : tag.trimmingCharacters(in: .whitespacesAndNewlines),
            groupName: groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "General" : groupName.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            expiresAt: hasExpiry ? expiresAt : nil,
            notes: notes,
            customFields: customFields.filter {
                !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.value.isEmpty
            },
            totpSecretBase32: totpSecretBase32.trimmingCharacters(in: .whitespacesAndNewlines),
            totpIssuer: totpIssuer.trimmingCharacters(in: .whitespacesAndNewlines),
            totpAccount: totpAccount.trimmingCharacters(in: .whitespacesAndNewlines),
            totpPeriod: max(totpPeriod, 1),
            totpDigits: max(totpDigits, 1),
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}
