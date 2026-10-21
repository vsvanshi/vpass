import AuthenticationServices
import Combine
import Foundation

public enum AutoFillMode: Sendable {
    case password
    case oneTimeCode

    public init(requestType: ASCredentialRequestType) {
        if #available(iOS 18.0, macOS 15.0, *), requestType == .oneTimeCode {
            self = .oneTimeCode
        } else {
            self = .password
        }
    }
}

@MainActor
public final class AutoFillModel: ObservableObject {
    @Published public private(set) var records: [CredentialRecord] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isOnScreen = false
    @Published public var searchText = ""

    public let mode: AutoFillMode
    /// Set when the user tapped a suggestion above the keyboard: fill that
    /// record right after Face ID instead of showing the list.
    public let directRecordID: UUID?
    private let pages: [AutoFillPage]
    private let onSelect: (CredentialRecord) -> Void
    private let onCancel: (ASExtensionError.Code) -> Void
    private let loadRecords: () throws -> [CredentialRecord]

    /// `loadRecords` reads the vault without changing it; each app passes its
    /// own Keychain reader.
    public init(
        mode: AutoFillMode,
        serviceIdentifiers: [ASCredentialServiceIdentifier],
        directRecordID: UUID?,
        loadRecords: @escaping () throws -> [CredentialRecord],
        onSelect: @escaping (CredentialRecord) -> Void,
        onCancel: @escaping (ASExtensionError.Code) -> Void
    ) {
        self.loadRecords = loadRecords
        self.mode = mode
        self.directRecordID = directRecordID
        self.pages = serviceIdentifiers.map { AutoFillPage(serviceIdentifier: $0.identifier) }
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    /// The site to name in the UI; for a single sign-on page this is the app
    /// being signed in to, not the shared login host.
    public var site: String? {
        pages.lazy.compactMap(\.displayHost).first
    }

    public var title: String {
        mode == .oneTimeCode ? "Verification Codes" : "Passwords"
    }

    /// Logins that fit the page, best first.
    public var suggested: [CredentialRecord] {
        records
            .filter { score($0) > 0 && $0.matchesSearch(searchText) }
            .sorted { score($0) > score($1) }
    }

    public var others: [CredentialRecord] {
        records.filter { score($0) == 0 && $0.matchesSearch(searchText) }
    }

    /// The one login that clearly belongs to this page (the app an SSO page
    /// signs in to, or the exact host), or nil when it's ambiguous.
    public var bestMatch: CredentialRecord? {
        let ranked = suggested
        guard let first = ranked.first, score(first) >= 2 else {
            return nil
        }
        if ranked.count > 1, score(ranked[1]) == score(first) {
            return nil
        }
        return first
    }

    public func sheetDidAppear() {
        isOnScreen = true
    }

    public func didUnlock() {
        let loaded: [CredentialRecord]
        do {
            loaded = try loadRecords()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Keep the keyboard suggestions in step with the vault, e.g. after a
        // credential was deleted on another device.
        Task { await CredentialIdentitySync.update(with: loaded) }

        if let directRecordID {
            guard let record = loaded.first(where: { $0.id == directRecordID }), isEligible(record) else {
                onCancel(.credentialIdentityNotFound)
                return
            }
            onSelect(record)
            return
        }

        records = loaded
            .filter(isEligible)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        errorMessage = nil
    }

    public func select(_ record: CredentialRecord) {
        onSelect(record)
    }

    public func cancel() {
        onCancel(.userCanceled)
    }

    private func isEligible(_ record: CredentialRecord) -> Bool {
        switch mode {
        case .password:
            !record.password.isEmpty
        case .oneTimeCode:
            record.hasTOTP
        }
    }

    private func score(_ record: CredentialRecord) -> Int {
        pages.map { record.autofillScore(for: $0) }.max() ?? 0
    }
}
