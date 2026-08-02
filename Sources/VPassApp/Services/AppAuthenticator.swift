import AppKit
import Foundation
import LocalAuthentication

@MainActor
final class AppAuthenticator: ObservableObject {
    static let shared = AppAuthenticator()

    static let autoLockMinutesDefaultsKey = "security.autoLockMinutes"
    static let autoLockMinutesDefault = 10

    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let authenticationGraceInterval: TimeInterval = 60
    private var lastAuthenticatedAt: Date?

    private var activityMonitor: Any?
    private var idleCheckTimer: Timer?
    private var lastActivityAt = Date()

    private init() {}

    // 0 means never auto-lock. Read from defaults on every idle check so a
    // changed setting applies immediately without re-arming anything.
    private var autoLockMinutes: Int {
        UserDefaults.standard.object(forKey: Self.autoLockMinutesDefaultsKey) as? Int
            ?? Self.autoLockMinutesDefault
    }

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
        startIdleMonitoring()
        return true
    }

    func lock() {
        isUnlocked = false
        isAuthenticating = false
        errorMessage = nil
        stopIdleMonitoring()
    }

    private func markAuthenticated() {
        lastAuthenticatedAt = Date()
        isUnlocked = true
        errorMessage = nil
        startIdleMonitoring()
    }

    // MARK: - Idle auto-lock

    // "Idle" means no keyboard/mouse events reaching VPass — using another app
    // counts as idle here, which is what you want for an unlocked vault
    // sitting in the background.
    private func startIdleMonitoring() {
        lastActivityAt = Date()

        if activityMonitor == nil {
            activityMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved]
            ) { event in
                MainActor.assumeIsolated {
                    AppAuthenticator.shared.lastActivityAt = Date()
                }
                return event
            }
        }

        idleCheckTimer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { _ in
            MainActor.assumeIsolated {
                AppAuthenticator.shared.lockIfIdle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleCheckTimer = timer
    }

    private func stopIdleMonitoring() {
        if let activityMonitor {
            NSEvent.removeMonitor(activityMonitor)
            self.activityMonitor = nil
        }
        idleCheckTimer?.invalidate()
        idleCheckTimer = nil
    }

    private func lockIfIdle() {
        guard isUnlocked else {
            return
        }
        let minutes = autoLockMinutes
        guard minutes > 0 else {
            return
        }
        if Date().timeIntervalSince(lastActivityAt) >= TimeInterval(minutes) * 60 {
            lock()
        }
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
