import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    @EnvironmentObject private var authenticator: AppAuthenticator
    // Keeps the Expired / Next 30d counts recomputing as the day rolls over.
    @ObservedObject private var dayClock = DayClock.shared
    @AppStorage("layout.passwordListColumnWidth") private var passwordListColumnWidth = 360.0
    @AppStorage("layout.sidebarColumnWidth") private var sidebarColumnWidth = 220.0
    @State private var showingSettings = false

    var body: some View {
        // Keep the split view alive while locked (overlay instead of swapping
        // it out): destroying it is what loses the user's column widths, and
        // SwiftUI offers no API to persist them across recreation.
        ZStack {
            unlockedContent
                .disabled(!authenticator.isUnlocked)

            if !authenticator.isUnlocked {
                LockedVaultView()
                    .environmentObject(authenticator)
            }
        }
        .frame(minWidth: 1040, minHeight: 640)
        .alert("VPass", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Unlock Failed", isPresented: Binding(
            get: { authenticator.errorMessage != nil },
            set: { if !$0 { authenticator.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authenticator.errorMessage ?? "")
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(viewModel)
                .frame(width: 540, height: 620)
        }
        .onAppear {
            authenticator.unlockIfRecentlyAuthenticated()
        }
        // The red close button bypasses applicationShouldTerminate, so without
        // this the vault stayed unlocked indefinitely and the Dock icon stuck
        // around with no window. Mirror the ⌘Q path: lock and drop to the menu
        // bar. The policy switch is deferred a runloop turn — flipping it
        // inside willClose (while the window is still key) can leave the Dock
        // icon behind.
        .background(WindowCloseObserver {
            AppAuthenticator.shared.lock()
            DispatchQueue.main.async {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        })
    }

    private var unlockedContent: some View {
        NavigationSplitView {
            tagSidebar
        } content: {
            passwordList
        } detail: {
            detailPane
        }
        .toolbar(authenticator.isUnlocked ? .visible : .hidden, for: .windowToolbar)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let draft = viewModel.editor {
            CredentialEditorView(initialDraft: draft, groupsByTag: viewModel.groupsByTag) { updatedDraft in
                viewModel.saveDraft(updatedDraft)
            } onCancel: {
                viewModel.editor = nil
            }
            .id(draft.id)
        } else {
            DetailView(record: viewModel.selectedRecord)
                .environmentObject(viewModel)
                .navigationSplitViewColumnWidth(min: 420, ideal: 720)
        }
    }

    private var sidebarIdealWidth: CGFloat {
        CGFloat(min(max(sidebarColumnWidth, 180), 260))
    }

    private var tagSidebar: some View {
        List(selection: $viewModel.selectedTag) {
            Section("Tags") {
                ForEach(VaultTag.all) { tag in
                    HStack {
                        Label(tag.name, systemImage: tag.systemImage)
                        Spacer()
                        Text("\(viewModel.count(for: tag))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(tag.name)
                }
            }
        }
        .navigationTitle("VPass")
        .frame(minWidth: 180, idealWidth: sidebarIdealWidth, maxWidth: 260)
        .navigationSplitViewColumnWidth(min: 180, ideal: sidebarIdealWidth, max: 260)
        .background(ColumnWidthReporter(range: 180...260, storedWidth: $sidebarColumnWidth))
        .onChange(of: viewModel.selectedTag) { _, newValue in
            if let tag = VaultTag.all.first(where: { $0.name == newValue }) {
                viewModel.selectTag(tag)
            }
        }
    }

    private var passwordList: some View {
        VStack(spacing: 0) {
            if !viewModel.selectedTagRecords.isEmpty {
                ExpirySummaryRow(summary: viewModel.selectedTagExpirySummary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            List(selection: $viewModel.selectedID) {
                ForEach(viewModel.groupedRecords, id: \.group) { group in
                    Section {
                        ForEach(group.records) { record in
                            CredentialListRow(record: record)
                                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 8))
                                .tag(record.id)
                        }
                    } header: {
                        HStack {
                            Text(group.group)
                            Spacer()
                            Text("\(group.records.count)")
                                .monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if viewModel.selectedTagRecords.isEmpty {
                    ContentUnavailableView("No \(viewModel.selectedTag) Passwords", systemImage: "folder", description: Text("Add your first credential here."))
                } else if viewModel.filteredRecords.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                }
            }
        }
        .navigationTitle(viewModel.selectedTag)
        .navigationSplitViewColumnWidth(
            min: 280,
            ideal: CGFloat(min(max(passwordListColumnWidth, 280), 760)),
            max: 760
        )
        .background(ColumnWidthReporter(range: 280...760, storedWidth: $passwordListColumnWidth))
        .searchable(text: $viewModel.searchText, placement: .toolbar)
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.backUpNow()
                } label: {
                    Label("Back Up Now", systemImage: "externaldrive.badge.plus")
                }
                .disabled(viewModel.isAutomaticBackupRunning)
                .help("Back Up Now")
            }

            ToolbarItem {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }

            ToolbarItem {
                Button {
                    viewModel.startNew()
                } label: {
                    Label("Add Password", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

}

/// Runs `onClose` when the window hosting this view closes. Scoped to that
/// specific NSWindow so sheets, Sparkle dialogs, and other windows don't
/// trigger it. Note: hide-to-menu-bar uses orderOut, which does NOT fire
/// willClose, so the ⌘Q path never double-locks through this.
private struct WindowCloseObserver: NSViewRepresentable {
    let onClose: @MainActor @Sendable () -> Void

    func makeNSView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        let coordinator = context.coordinator
        let onClose = onClose
        view.onWindowChange = { window in
            coordinator.attach(to: window, onClose: onClose)
        }
        return view
    }

    func updateNSView(_ nsView: WindowObservingView, context: Context) {
        context.coordinator.attach(to: nsView.window, onClose: onClose)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class WindowObservingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private var token: NSObjectProtocol?

        func attach(to window: NSWindow?, onClose: @escaping @MainActor @Sendable () -> Void) {
            guard let window, window !== observedWindow else {
                return
            }
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
            observedWindow = window
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    onClose()
                }
            }
        }
    }
}

/// Persists a navigation column's live width so it can be fed back as the
/// column's `ideal` width on the next app launch. Within a session the
/// columns keep their size because the split view is never torn down.
private struct ColumnWidthReporter: View {
    let range: ClosedRange<Double>
    @Binding var storedWidth: Double

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size.width) { _, newValue in
                    let width = Double(newValue.rounded())
                    guard range.contains(width), abs(storedWidth - width) >= 1 else {
                        return
                    }
                    // Defer the write: mutating AppStorage while the split view
                    // is mid-layout trips AppKit's layoutSubtreeIfNeeded
                    // recursion warning.
                    DispatchQueue.main.async {
                        storedWidth = width
                    }
                }
        }
    }
}

private struct LockedVaultView: View {
    @EnvironmentObject private var authenticator: AppAuthenticator

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 82, height: 82)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 6) {
                Text("VPass is Locked")
                    .font(.title2.weight(.semibold))
                Text("Use Touch ID or your Mac password to unlock your vault.")
                    .foregroundStyle(.secondary)
            }

            Button {
                authenticator.authenticate()
            } label: {
                Label(authenticator.isAuthenticating ? "Unlocking..." : "Unlock VPass", systemImage: "touchid")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(authenticator.isAuthenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAuthenticator.autoLockMinutesDefaultsKey)
    private var autoLockMinutes = AppAuthenticator.autoLockMinutesDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    securitySection
                    recoverySection
                    totpSyncSection
                }
            }

            Text("Restore adds missing credentials and updates matching credentials. It does not delete other current credentials.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(22)
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Security", systemImage: "lock.shield")
                .font(.headline)

            HStack {
                Text("Auto-lock after inactivity")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Auto-lock after inactivity", selection: $autoLockMinutes) {
                    Text("Never").tag(0)
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
                .labelsHidden()
                .frame(width: 140)
            }
            .font(.subheadline)

            Text("Locks the vault when VPass hasn't been used for this long. Closing the window locks it immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recovery", systemImage: "externaldrive.badge.checkmark")
                .font(.headline)

            SettingsInfoRow(
                title: "Backup password",
                value: viewModel.isAutomaticBackupConfigured ? "Saved in Keychain" : "Not set"
            )
            SettingsInfoRow(title: "Latest backup", value: viewModel.backupHealth.latestBackupText)
            SettingsInfoRow(title: "Previous backup", value: viewModel.backupHealth.previousBackupText)
            SettingsInfoRow(title: "Pending changes", value: pendingChangesText)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.backUpNow()
                    } label: {
                        Label("Back Up Now", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(viewModel.isAutomaticBackupRunning)

                    Button {
                        viewModel.exportEncryptedBackup()
                    } label: {
                        Label("Export File", systemImage: "square.and.arrow.up")
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        viewModel.restoreCurrentBackup()
                    } label: {
                        Label("Restore Latest", systemImage: "arrow.down.doc")
                    }
                    .disabled(!viewModel.backupHealth.hasCurrentBackup)

                    Button {
                        viewModel.restorePreviousBackup()
                    } label: {
                        Label("Restore Previous", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(!viewModel.backupHealth.hasPreviousBackup)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    viewModel.setUpAutomaticBackup()
                } label: {
                    Label(
                        viewModel.isAutomaticBackupConfigured ? "Change Backup Password" : "Set Up Backup",
                        systemImage: "key"
                    )
                }

                Button(role: .destructive) {
                    viewModel.disableAutomaticBackup()
                } label: {
                    Label("Disable Backup", systemImage: "trash")
                }
                .disabled(!viewModel.isAutomaticBackupConfigured)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var totpSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("iCloud Vault Sync", systemImage: "icloud")
                .font(.headline)

            SettingsInfoRow(title: "Status", value: viewModel.isCloudKeychainSyncAvailable ? "Automatic" : "Unavailable in this build")
            SettingsInfoRow(title: "Credentials", value: "\(viewModel.records.count)")
            SettingsInfoRow(title: "Authenticators", value: "\(viewModel.totpSyncCredentialCount)")

            Text(viewModel.isCloudKeychainSyncAvailable ? "Credentials and authenticator secrets are stored in your shared iCloud Keychain access group for VPass on Mac and iPhone." : "The GitHub Developer ID build is local-only until it is signed with a shared keychain provisioning profile.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                viewModel.recoverLocalOnlyCredentials()
            } label: {
                Label("Recover Local Items", systemImage: "key.icloud")
            }
            .disabled(!viewModel.isCloudKeychainSyncAvailable)
            .help("Recover older local-only credentials and TOTP secrets into the shared iCloud vault")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pendingChangesText: String {
        let count = viewModel.backupHealth.changedRecordCount
        if count == 0 {
            return "None"
        }
        if count == 1 {
            return "1 credential"
        }
        return "\(count) credentials"
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
    }
}

private struct ExpirySummaryRow: View {
    let summary: ExpirySummary

    var body: some View {
        HStack(spacing: 8) {
            ExpiryMetric(
                title: "Expired",
                value: summary.expired,
                systemImage: "exclamationmark.triangle.fill",
                color: summary.expired > 0 ? .red : .secondary
            )
            ExpiryMetric(
                title: "Next 30d",
                value: summary.expiringSoon,
                systemImage: "calendar.badge.clock",
                color: summary.expiringSoon > 0 ? .orange : .secondary
            )
            ExpiryMetric(
                title: "No expiry",
                value: summary.withoutExpiry,
                systemImage: "calendar.badge.minus",
                color: .secondary
            )
        }
    }
}

private struct ExpiryMetric: View {
    let title: String
    let value: Int
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 16)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(value)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CredentialListRow: View {
    // List rows only re-render when their inputs change, so the day-based
    // labels below have to observe the clock or they freeze at launch day.
    @ObservedObject private var dayClock = DayClock.shared
    let record: CredentialRecord

    private var displayTitle: String {
        record.title.isEmpty ? "Untitled" : record.title
    }

    private var primaryDetail: String {
        if !record.username.isEmpty {
            return record.username
        }
        if !record.url.isEmpty {
            return record.url
        }
        return "No username"
    }

    private var secondaryLine: String {
        let detail = primaryDetail
        let group = record.groupName.isEmpty ? "General" : record.groupName
        guard !group.isEmpty else {
            return detail
        }
        return "\(detail)  -  \(group)"
    }

    private var updatedText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(record.updatedAt) {
            return record.updatedAt.formatted(date: .omitted, time: .shortened)
        }
        if calendar.component(.year, from: record.updatedAt) == calendar.component(.year, from: Date()) {
            return record.updatedAt.formatted(.dateTime.day().month(.abbreviated))
        }
        return record.updatedAt.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private var expiryLabel: String? {
        guard let expiresAt = record.expiresAt else {
            return nil
        }
        return expiryText(for: expiresAt)
    }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.tint.opacity(0.10))
                Image(systemName: record.totpSecretBase32.isEmpty ? "key.fill" : "lock.rotation")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    if !record.totpSecretBase32.isEmpty {
                        Image(systemName: "number.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .help("Authenticator configured")
                    }
                }

                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                if let expiryLabel {
                    Text(expiryLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(record.expiresAt.map { expiryColor(for: $0) } ?? .secondary)
                        .lineLimit(1)
                }

                Text(updatedText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 86, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private func expiryText(for date: Date) -> String {
        let days = daysUntil(date)
        if days < 0 {
            return "Expired"
        }
        if days == 0 {
            return "Expires today"
        }
        if days <= 30 {
            return "Expires in \(days)d"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func expiryColor(for date: Date) -> Color {
        let days = daysUntil(date)
        if days < 0 {
            return .red
        }
        if days <= 30 {
            return .orange
        }
        return .green
    }

    private func daysUntil(_ date: Date) -> Int {
        dayClock.daysUntil(date)
    }
}
