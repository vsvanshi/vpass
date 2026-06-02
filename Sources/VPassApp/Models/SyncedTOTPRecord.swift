import Foundation

struct SyncedTOTPRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var tag: String
    var groupName: String
    var title: String
    var username: String
    var issuer: String
    var account: String
    var secretBase32: String
    var period: Int
    var digits: Int
    var updatedAt: Date

    init?(_ record: CredentialRecord) {
        guard record.hasTOTP else {
            return nil
        }
        id = record.id
        tag = record.tag
        groupName = record.groupName.isEmpty ? "General" : record.groupName
        title = record.title
        username = record.username
        issuer = record.totpIssuer
        account = record.totpAccount.isEmpty ? record.username : record.totpAccount
        secretBase32 = record.totpSecretBase32
        period = max(record.totpPeriod, 1)
        digits = max(record.totpDigits, 1)
        updatedAt = record.updatedAt
    }
}

extension CredentialRecord {
    var hasTOTP: Bool {
        !totpSecretBase32.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
