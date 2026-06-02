import AppKit
import SwiftUI

@main
struct VPassApp: App {
    @NSApplicationDelegateAdaptor(VPassAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = VaultViewModel(vault: KeychainVault())
    @StateObject private var authenticator = AppAuthenticator.shared
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        MenuBarExtra("VPass", systemImage: "lock.shield") {
            MenuBarRootView(
                openMainWindow: {
                    appDelegate.showMainWindow(viewModel: viewModel)
                },
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
    private let windowController = VPassWindowController()
    private weak var lastViewModel: VaultViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        quitKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.isVPassQuitShortcut else {
                return event
            }
            NotificationCenter.default.post(name: .vPassHideMainWindow, object: nil)
            return nil
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowsQuit {
            return .terminateNow
        }

        NotificationCenter.default.post(name: .vPassHideMainWindow, object: nil)
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let lastViewModel {
            showMainWindow(viewModel: lastViewModel)
        }
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        windowController.keepWindowAvailableIfVisible()
    }

    func showMainWindow(viewModel: VaultViewModel) {
        lastViewModel = viewModel
        viewModel.reload()
        windowController.show(viewModel: viewModel)
    }

    func quitFromMenuBar() {
        allowsQuit = true
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
final class VPassWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hideObserver: NSObjectProtocol?
    private var activationTask: Task<Void, Never>?

    override init() {
        super.init()
        hideObserver = NotificationCenter.default.addObserver(
            forName: .vPassHideMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    func show(viewModel: VaultViewModel) {
        if let window {
            show(window)
            return
        }

        let contentView = ContentView()
            .environmentObject(viewModel)
            .environmentObject(AppAuthenticator.shared)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "VPass"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1120, height: 720))
        window.minSize = NSSize(width: 1040, height: 640)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.delegate = self
        window.center()

        self.window = window
        show(window)
    }

    func hide() {
        activationTask?.cancel()
        activationTask = nil

        window?.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        AppAuthenticator.shared.lock()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func keepWindowAvailableIfVisible() {
        if window?.isVisible == true {
            NSApplication.shared.setActivationPolicy(.regular)
        }
    }

    private func show(_ window: NSWindow) {
        activationTask?.cancel()
        NSApplication.shared.setActivationPolicy(.regular)
        AppAuthenticator.shared.unlockIfRecentlyAuthenticated()
        bringToFront(window)

        activationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, window.isVisible else {
                return
            }
            NSApplication.shared.setActivationPolicy(.regular)
            bringToFront(window)
        }
    }

    private func bringToFront(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

}

private extension Notification.Name {
    static let vPassHideMainWindow = Notification.Name("vPassHideMainWindow")
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

    let openMainWindow: () -> Void
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
                    openMainWindow()
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
}
