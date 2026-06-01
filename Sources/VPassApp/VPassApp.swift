import SwiftUI

@main
struct VPassApp: App {
    @StateObject private var viewModel = VaultViewModel(vault: KeychainVault())
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Password") {
                    viewModel.startNew()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }

        MenuBarExtra("VPass", systemImage: "lock.shield") {
            QuickSearchView()
                .environmentObject(viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
