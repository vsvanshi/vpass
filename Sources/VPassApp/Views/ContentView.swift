import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            tagSidebar
        } content: {
            passwordList
        } detail: {
            detailPane
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(viewModel)
                .frame(width: 520, height: 430)
        }
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
        }
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
        .frame(minWidth: 180)
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

private struct SettingsView: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    @Environment(\.dismiss) private var dismiss

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

            VStack(alignment: .leading, spacing: 12) {
                Label("Recovery", systemImage: "externaldrive.badge.shield.checkmark")
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
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            Text("Restore adds missing credentials and updates matching credentials. It does not delete other current credentials.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(22)
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
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
    }
}
