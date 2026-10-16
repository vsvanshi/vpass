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

    public func matchesAutofillService(_ serviceIdentifier: String) -> Bool {
        guard let domain = autofillDomain, let serviceHost = AutoFillDomain.host(from: serviceIdentifier) else {
            return false
        }
        return AutoFillDomain.matches(domain, serviceHost)
    }
}
