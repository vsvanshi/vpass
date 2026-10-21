import AppKit
import Combine
import SwiftUI

/// Spotlight-style search window opened by the keyboard shortcut. It is a
/// non-activating panel: it takes keyboard focus without activating VPass, so
/// the main window stays where it is and the browser stays in front for
/// pasting.
@MainActor
final class QuickSearchPanel {
    static let shared = QuickSearchPanel()

    private var panel: NSPanel?
    private var viewModel: VaultViewModel?
    private var observers: [NSObjectProtocol] = []
    private var unlockSubscription: AnyCancellable?

    private init() {}

    func configure(viewModel: VaultViewModel) {
        self.viewModel = viewModel
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
            return
        }
        QuickSearchContext.shared.didOpen()
        guard let panel = panel ?? makePanel() else {
            return
        }
        self.panel = panel
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - frame.height * 0.18))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel? {
        guard let viewModel else {
            return nil
        }
        let panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Fixed size: the list scrolls inside. Letting the window follow its
        // content resized it mid-click, which crashed AppKit's layout.
        let content = QuickSearchView(usesShortcutContext: true)
            .environmentObject(viewModel)
            .environmentObject(AppAuthenticator.shared)
            .frame(width: 420, height: 480, alignment: .top)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        let host = NSHostingController(rootView: content)
        host.sizingOptions = []
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 420, height: 480))

        // Click elsewhere to dismiss, like Spotlight, except while Touch ID
        // is up (that dialog takes key focus from the panel).
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if !AppAuthenticator.shared.isAuthenticating {
                    QuickSearchPanel.shared.hide()
                }
            }
        })
        // After unlocking, give the panel keyboard focus back.
        unlockSubscription = AppAuthenticator.shared.$isUnlocked
            .removeDuplicates()
            .filter { $0 }
            .sink { _ in
                MainActor.assumeIsolated {
                    if let panel = QuickSearchPanel.shared.panel, panel.isVisible {
                        panel.makeKey()
                    }
                }
            }
        return panel
    }
}

/// A borderless panel that can still take keyboard focus; Escape closes it.
private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

/// Focus handling shared by the shortcut window and the menu bar panel.
@MainActor
enum MenuBarPanel {
    /// The app that was in front before VPass, so focus can go back to it
    /// after copying from the menu bar panel (which does activate VPass).
    private static var previousAppPID: pid_t?

    static func startTrackingFrontmostApp() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { note in
            // Only the PID crosses into main-actor code; the notification
            // itself isn't Sendable.
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier,
                  pid != ProcessInfo.processInfo.processIdentifier else {
                return
            }
            MainActor.assumeIsolated {
                previousAppPID = pid
            }
        }
    }

    /// Hides the search (shortcut window and menu bar panel) and puts the
    /// previous app back in front, so a paste lands where the user was.
    static func closeAndReturnFocus() {
        QuickSearchPanel.shared.hide()
        NSApplication.shared.windows
            .filter { window in
                window.isVisible
                    && !window.styleMask.contains(.titled)
                    && window.level != .normal
                    && !window.className.contains("StatusBar")
            }
            .forEach { $0.orderOut(nil) }
        if NSApplication.shared.isActive, let previousAppPID {
            NSRunningApplication(processIdentifier: previousAppPID)?.activate(options: [])
        }
    }
}
