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
}

extension SyncedTOTPRecord {
    var displayGroup: String {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "General" : groupName
    }

    var displayAccount: String {
        if !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return account
        }
        return username
    }

    func matches(_ query: String) -> Bool {
        let tokens = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else {
            return true
        }

        let haystack = [
            title,
            username,
            issuer,
            account,
            tag,
            groupName
        ]
        .joined(separator: " ")
        .lowercased()

        return tokens.allSatisfy { haystack.contains($0) }
    }
}
