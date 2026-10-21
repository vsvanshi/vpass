import Foundation

public enum AutoFillDomain {
    /// Lowercased host for a Website field or an AutoFill service identifier,
    /// with any leading "www." removed. Accepts values with or without a scheme
    /// ("example.com", "https://login.example.com/path").
    public static func host(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var host = URL(string: candidate)?.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host.isEmpty ? nil : host
    }

    /// True when both hosts are the same site: equal, or one is a subdomain of
    /// the other. A dotless host ("com", "localhost") only matches exactly, so
    /// a bare suffix can never match every site.
    public static func matches(_ first: String, _ second: String) -> Bool {
        if first == second {
            return true
        }
        let (shorter, longer) = first.count < second.count ? (first, second) : (second, first)
        return shorter.contains(".") && longer.hasSuffix(".\(shorter)")
    }
}

extension CredentialRecord {
    /// The site this credential belongs to, taken from its Website field.
    public var autofillDomain: String? {
        AutoFillDomain.host(from: url)
    }

    /// The name AutoFill shows for this credential: the username, or the title
    /// when the username is empty.
    public var autofillUser: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }

    /// AutoFill suggestion labels keyed by record ID. When several logins share
    /// a username (one work email across many internal sites), each label
    /// leads with the record's VPass name so the suggestions can be told
    /// apart; otherwise the label is just the username.
    public static func autofillLabels(for records: [CredentialRecord]) -> [UUID: String] {
        let usernameCounts = Dictionary(grouping: records) { $0.autofillUser.lowercased() }
            .mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: records.map { record in
            let user = record.autofillUser
            let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let isShared = (usernameCounts[user.lowercased()] ?? 0) > 1
            guard isShared, !title.isEmpty, title.caseInsensitiveCompare(user) != .orderedSame else {
                return (record.id, user)
            }
            return (record.id, "\(title) - \(user)")
        })
    }

    public func matchesAutofillService(_ serviceIdentifier: String) -> Bool {
        guard let domain = autofillDomain, let serviceHost = AutoFillDomain.host(from: serviceIdentifier) else {
            return false
        }
        return AutoFillDomain.matches(domain, serviceHost)
    }
}

/// The page AutoFill was opened on, as far as matching is concerned. Single
/// sign-on pages (Keycloak, CAS, SAML) live on a shared login host, so the app
/// being signed in to is read from the page's redirect parameters and from a
/// Keycloak `realms/<name>` path.
public struct AutoFillPage: Sendable, Equatable {
    public struct Target: Sendable, Equatable {
        public let host: String
        public let pathComponents: [String]
    }

    /// Host of the page itself, e.g. the shared SSO host.
    public let host: String?
    /// Sites the page signs in to, taken from query values that are URLs
    /// (redirect_uri, service, RelayState, return_to, ...).
    public let targets: [Target]
    /// Keycloak realm from a `/realms/<name>/` path, lowercased.
    public let realm: String?

    public init(serviceIdentifier: String) {
        let trimmed = serviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = URLComponents(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
        host = AutoFillDomain.host(from: trimmed)
        targets = (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://"),
                  let host = AutoFillDomain.host(from: value) else {
                return nil
            }
            return Target(host: host, pathComponents: Self.pathComponents(of: URLComponents(string: value)?.path ?? ""))
        }
        let pagePath = Self.pathComponents(of: components?.path ?? "")
        if let index = pagePath.firstIndex(of: "realms"), index + 1 < pagePath.count {
            realm = pagePath[index + 1]
        } else {
            realm = nil
        }
    }

    /// The site to name in the UI: the app being signed in to when known.
    public var displayHost: String? {
        targets.first?.host ?? host
    }

    static func pathComponents(of path: String) -> [String] {
        path.lowercased().split(separator: "/").map(String.init)
    }
}

extension CredentialRecord {
    /// How well this login fits the page: 3 = the app being signed in to
    /// (redirect target or Keycloak realm), 2 = same host, 1 = related
    /// subdomain, 0 = unrelated.
    public func autofillScore(for page: AutoFillPage) -> Int {
        guard let domain = autofillDomain else {
            return 0
        }
        let recordPath = AutoFillPage.pathComponents(of: URLComponents(string: url.contains("://") ? url : "https://\(url)")?.path ?? "")

        if page.targets.contains(where: { $0.host == domain && Self.pathsOverlap(recordPath, $0.pathComponents) }) {
            return 3
        }
        if let realm = page.realm, realm.count >= 3, recordPath.contains(realm) {
            return 3
        }
        if page.host == domain || page.targets.contains(where: { $0.host == domain }) {
            return 2
        }
        if let host = page.host, AutoFillDomain.matches(domain, host) {
            return 1
        }
        return 0
    }

    /// True when one path is a component-wise prefix of the other; an empty
    /// path (just a host) overlaps everything.
    private static func pathsOverlap(_ first: [String], _ second: [String]) -> Bool {
        let shorter = first.count <= second.count ? first : second
        let longer = first.count <= second.count ? second : first
        return Array(longer.prefix(shorter.count)) == shorter
    }
}
