import AppKit
import SwiftUI

@main
struct VPassApp: App {
    @NSApplicationDelegateAdaptor(VPassAppDelegate.self) private var appDelegate
    @StateObject private var viewModel: VaultViewModel
    @StateObject private var authenticator: AppAuthenticator
    @StateObject private var updater: AppUpdater

    init() {
        let viewModel = VaultViewModel(vault: KeychainVault())
        _viewModel = StateObject(wrappedValue: viewModel)
        _authenticator = StateObject(wrappedValue: AppAuthenticator.shared)
        _updater = StateObject(wrappedValue: AppUpdater())
    }

    var body: some Scene {
        // Single, unique window (not WindowGroup) so "Open VPass" reuses one
        // instance instead of spawning a new window each time.
        Window("VPass", id: "main") {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(authenticator)
        }
        .defaultSize(width: 1120, height: 720)

        MenuBarExtra("VPass", systemImage: "lock.shield") {
            MenuBarRootView(
                checkForUpdates: {
                    updater.checkForUpdates()
                },
                canCheckForUpdates: updater.canCheckForUpdates,
                quit: {
                    appDelegate.quitFromMenuBar()
                }
            )
                .environmentObject(viewModel)
                .environmentObject(authenticator)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class VPassAppDelegate: NSObject, NSApplicationDelegate {
    private var allowsQuit = false
    private var quitKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        quitKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.isVPassQuitShortcut else {
                return event
            }
            self.hideWindows()
            return nil
        }
        // Sparkle needs the app to actually terminate to relaunch the updated
        // build; this lets it bypass the "hide instead of quit" behavior.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(allowTerminationForUpdate),
            name: .vPassAllowTerminationForUpdate,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(revokeTerminationForUpdate),
            name: .vPassRevokeTerminationForUpdate,
            object: nil
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowsQuit || isSystemInitiatedTermination {
            return .terminateNow
        }

        hideWindows()
        return .terminateCancel
    }

    // Logout, shutdown, and restart deliver a quit Apple event that carries a
    // kAEQuitReason ("why?") attribute; user-initiated quits don't. Cancelling
    // those makes macOS abort the whole logout with "VPass interrupted
    // shutdown", so let them through (the process is going away regardless).
    private var isSystemInitiatedTermination: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication) else {
            return false
        }
        return event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
    }

    @objc private func allowTerminationForUpdate() {
        allowsQuit = true
    }

    @objc private func revokeTerminationForUpdate() {
        allowsQuit = false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindows()
        return true
    }

    func quitFromMenuBar() {
        allowsQuit = true
        NSApplication.shared.terminate(nil)
    }

    private func hideWindows() {
        mainWindows.forEach { window in
            window.orderOut(nil)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        AppAuthenticator.shared.lock()
    }

    private func showWindows() {
        NSApplication.shared.setActivationPolicy(.regular)
        mainWindows.forEach { window in
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private var mainWindows: [NSWindow] {
        NSApplication.shared.windows.filter { window in
            window.styleMask.contains(.titled)
        }
    }
}

private extension NSEvent {
    var isVPassQuitShortcut: Bool {
        type == .keyDown
            && modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && charactersIgnoringModifiers?.localizedLowercase == "q"
    }
}

private struct MenuBarRootView: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    @Environment(\.openWindow) private var openWindow

    let checkForUpdates: () -> Void
    let canCheckForUpdates: Bool
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            QuickSearchView()
                .environmentObject(viewModel)

            Divider()

            HStack(spacing: 10) {
                Button {
                    showMainWindow()
                } label: {
                    Label("Open VPass", systemImage: "macwindow")
                }

                Spacer()

                Button {
                    checkForUpdates()
                } label: {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!canCheckForUpdates)

                Button(role: .destructive) {
                    quit()
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 420)
    }

    private func showMainWindow() {
        // The tray panel doesn't auto-dismiss on button clicks and holds key
        // status; while it's up, the main window orders front but never
        // becomes key. Close it before handing focus over.
        for window in NSApplication.shared.windows
        where window.isVisible && !window.styleMask.contains(.titled) && window.level != .normal {
            window.orderOut(nil)
        }

        NSApplication.shared.setActivationPolicy(.regular)
        // Reuse the existing main window if it's around (even if hidden via
        // orderOut); only create one if none exists. Prevents duplicate windows.
        if let existing = NSApplication.shared.windows.first(where: { $0.styleMask.contains(.titled) }) {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        // Activating in the same runloop turn as the accessory→regular policy
        // flip silently fails; defer so activation targets the (re)created
        // window. The second, delayed pass covers openWindow's window not
        // existing yet on the first turn.
        for delay in [0.0, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows
                    .first { $0.styleMask.contains(.titled) }?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }
}
