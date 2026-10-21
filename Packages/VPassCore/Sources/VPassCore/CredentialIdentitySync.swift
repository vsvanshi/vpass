import AuthenticationServices

/// Publishes each credential's site and username (never its password or TOTP
/// secret) to iOS, so VPass logins and codes appear above the keyboard.
/// Used by both apps and both AutoFill extensions.
@MainActor
public enum CredentialIdentitySync {
    public static func update(with records: [CredentialRecord]) async {
        let store = ASCredentialIdentityStore.shared
        guard await store.state().isEnabled else {
            return
        }
        try? await store.replaceCredentialIdentities(identities(for: records))
    }

    public static func identities(for records: [CredentialRecord]) -> [any ASCredentialIdentity] {
        let passwordRecords = records.filter { $0.autofillDomain != nil && !$0.password.isEmpty }
        let labels = CredentialRecord.autofillLabels(for: passwordRecords)
        return records.flatMap { record -> [any ASCredentialIdentity] in
            guard let domain = record.autofillDomain else {
                return []
            }
            let service = ASCredentialServiceIdentifier(identifier: domain, type: .domain)
            let recordID = record.id.uuidString
            var identities: [any ASCredentialIdentity] = []
            if !record.password.isEmpty {
                let user = labels[record.id] ?? record.autofillUser
                identities.append(ASPasswordCredentialIdentity(serviceIdentifier: service, user: user, recordIdentifier: recordID))
            }
            if #available(iOS 18.0, macOS 15.0, *), record.hasTOTP {
                let label = record.title.isEmpty ? record.autofillUser : record.title
                identities.append(ASOneTimeCodeCredentialIdentity(serviceIdentifier: service, label: label, recordIdentifier: recordID))
            }
            return identities
        }
    }
}
