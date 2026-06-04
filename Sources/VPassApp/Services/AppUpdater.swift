import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
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
}

extension Notification.Name {
    static let vPassAllowTerminationForUpdate = Notification.Name("vPassAllowTerminationForUpdate")
}
