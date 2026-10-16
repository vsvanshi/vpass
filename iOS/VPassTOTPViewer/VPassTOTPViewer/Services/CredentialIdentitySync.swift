import AuthenticationServices
import VPassCore

/// Publishes each credential's site and username (never its password or TOTP
/// secret) to iOS, so VPass logins and codes appear above the keyboard.
/// Compiled into both the app and the AutoFill extension.
enum CredentialIdentitySync {
    static func update(with records: [CredentialRecord]) async {
        let store = ASCredentialIdentityStore.shared
        guard await store.state().isEnabled else {
            return
        }
        try? await store.replaceCredentialIdentities(identities(for: records))
    }

    static func identities(for records: [CredentialRecord]) -> [any ASCredentialIdentity] {
        records.flatMap { record -> [any ASCredentialIdentity] in
            guard let domain = record.autofillDomain else {
                return []
            }
            let service = ASCredentialServiceIdentifier(identifier: domain, type: .domain)
            let recordID = record.id.uuidString
            var identities: [any ASCredentialIdentity] = []
            if !record.password.isEmpty {
                identities.append(ASPasswordCredentialIdentity(serviceIdentifier: service, user: record.autofillUser, recordIdentifier: recordID))
            }
            if #available(iOS 18.0, *), record.hasTOTP {
                let label = record.title.isEmpty ? record.autofillUser : record.title
                identities.append(ASOneTimeCodeCredentialIdentity(serviceIdentifier: service, label: label, recordIdentifier: recordID))
            }
            return identities
        }
    }
}
