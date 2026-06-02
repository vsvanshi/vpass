import AppKit
import SwiftUI

@main
struct VPassApp: App {
    @NSApplicationDelegateAdaptor(VPassAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = VaultViewModel(vault: KeychainVault())
    @StateObject private var updater = AppUpdater()
    @StateObject private var windowController = VPassWindowController()

    var body: some Scene {
        MenuBarExtra("VPass", systemImage: "lock.shield") {
            MenuBarRootView(
                openMainWindow: {
                    windowController.show(viewModel: viewModel)
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
        }
        .menuBarExtraStyle(.window)
    }
}

final class VPassAppDelegate: NSObject, NSApplicationDelegate {
    private var allowsQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowsQuit {
            return .terminateNow
        }

        if let event = sender.currentEvent,
           event.type == .keyDown,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.localizedLowercase == "q" {
            return .terminateCancel
        }

        return .terminateNow
    }

    @MainActor
    func quitFromMenuBar() {
        allowsQuit = true
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
final class VPassWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(viewModel: VaultViewModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            return
        }

        let contentView = ContentView()
            .environmentObject(viewModel)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "VPass"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1120, height: 720))
        window.minSize = NSSize(width: 1040, height: 640)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        window = nil
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
