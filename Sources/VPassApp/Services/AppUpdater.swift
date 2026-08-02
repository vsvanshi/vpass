import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    // Mirrored from the updater via KVO so the menu bar button state stays
    // live; reading updater.canCheckForUpdates directly in a view body gives
    // SwiftUI nothing to observe and the value freezes at first render.
    @Published private(set) var canCheckForUpdates = false

    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    @objc nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // The app delegate cancels ordinary termination so closing the window
        // only hides the app to the menu bar. Sparkle must be allowed to
        // actually quit to swap in the new build, so signal the delegate to
        // permit termination. Posted synchronously on the main thread, so the
        // flag is set before Sparkle's terminate reaches applicationShouldTerminate.
        NotificationCenter.default.post(name: .vPassAllowTerminationForUpdate, object: nil)
    }

    @objc nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        // If a cycle dies after updaterWillRelaunchApplication armed the quit
        // flag (e.g. the user cancelled the installer's auth prompt), disarm
        // it so a later plain quit request goes back to hiding, not quitting.
        if error != nil {
            NotificationCenter.default.post(name: .vPassRevokeTerminationForUpdate, object: nil)
        }
    }
}

extension Notification.Name {
    static let vPassAllowTerminationForUpdate = Notification.Name("vPassAllowTerminationForUpdate")
    static let vPassRevokeTerminationForUpdate = Notification.Name("vPassRevokeTerminationForUpdate")
}
