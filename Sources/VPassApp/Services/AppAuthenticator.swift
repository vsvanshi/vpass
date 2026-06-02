import Foundation
import LocalAuthentication

@MainActor
final class AppAuthenticator: ObservableObject {
    static let shared = AppAuthenticator()

    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let authenticationGraceInterval: TimeInterval = 60
    private var lastAuthenticatedAt: Date?

    private init() {}

    func authenticate(reason: String = "Unlock VPass to access your credentials.") {
        if unlockIfRecentlyAuthenticated() {
            return
        }

        guard !isAuthenticating else {
            return
        }

        isAuthenticating = true
        errorMessage = nil

        Task {
            do {
                try await evaluate(reason: reason)
                markAuthenticated()
            } catch {
                if !isCancellation(error) {
                    errorMessage = error.localizedDescription
                }
            }
            isAuthenticating = false
        }
    }

    @discardableResult
    func unlockIfRecentlyAuthenticated(now: Date = Date()) -> Bool {
        guard let lastAuthenticatedAt,
              now.timeIntervalSince(lastAuthenticatedAt) <= authenticationGraceInterval else {
            return false
        }

        isUnlocked = true
        isAuthenticating = false
        errorMessage = nil
        return true
    }

    func lock() {
        isUnlocked = false
        isAuthenticating = false
        errorMessage = nil
    }

    private func markAuthenticated() {
        lastAuthenticatedAt = Date()
        isUnlocked = true
        errorMessage = nil
    }

    private nonisolated func evaluate(reason: String) async throws {
        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw authError ?? AuthError.unavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? AuthError.failed)
                }
            }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        guard let laError = error as? LAError else {
            return false
        }
        return laError.code == .userCancel || laError.code == .systemCancel || laError.code == .appCancel
    }
}

private enum AuthError: LocalizedError {
    case unavailable
    case failed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Device authentication is not available. Set up Touch ID or a Mac password and try again."
        case .failed:
            "VPass could not verify your identity."
        }
    }
}
