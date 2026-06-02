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

    enum CodingKeys: String, CodingKey {
        case id
        case tag
        case groupName
        case title
        case username
        case password
        case url
        case expiresAt
        case notes
        case customFields
        case totpSecretBase32
        case totpIssuer
        case totpAccount
        case totpPeriod
        case totpDigits
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? VaultTag.personal.name
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? "General"
        title = try container.decode(String.self, forKey: .title)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        url = try container.decode(String.self, forKey: .url)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        notes = try container.decode(String.self, forKey: .notes)
        customFields = try container.decode([CustomField].self, forKey: .customFields)
        totpSecretBase32 = try container.decode(String.self, forKey: .totpSecretBase32)
        totpIssuer = try container.decode(String.self, forKey: .totpIssuer)
        totpAccount = try container.decode(String.self, forKey: .totpAccount)
        totpPeriod = try container.decode(Int.self, forKey: .totpPeriod)
        totpDigits = try container.decode(Int.self, forKey: .totpDigits)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

extension CredentialRecord {
    func matchesSearch(_ query: String) -> Bool {
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
        self.id = record.id
        self.tag = record.tag
        self.groupName = record.groupName
        self.title = record.title
        self.username = record.username
        self.password = record.password
        self.url = record.url
        self.hasExpiry = record.expiresAt != nil
        self.expiresAt = record.expiresAt ?? Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        self.notes = record.notes
        self.customFields = record.customFields
        self.totpSecretBase32 = record.totpSecretBase32
        self.totpIssuer = record.totpIssuer
        self.totpAccount = record.totpAccount
        self.totpPeriod = record.totpPeriod
        self.totpDigits = record.totpDigits
        self.createdAt = record.createdAt
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
