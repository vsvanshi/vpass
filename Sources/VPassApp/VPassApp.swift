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
            CommandGroup(after: .newItem) {
                Button("Export Encrypted Backup...") {
                    viewModel.exportEncryptedBackup()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Import Encrypted Backup...") {
                    viewModel.importEncryptedBackup()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
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
