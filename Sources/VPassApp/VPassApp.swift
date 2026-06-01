import SwiftUI

@main
struct VPassApp: App {
    @StateObject private var viewModel = VaultViewModel(vault: KeychainVault())

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
        }

        MenuBarExtra("VPass", systemImage: "lock.shield") {
            QuickSearchView()
                .environmentObject(viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
