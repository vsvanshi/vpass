import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: VaultViewModel

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
            if viewModel.backupHealth.needsAttention || !viewModel.selectedTagRecords.isEmpty {
                VStack(spacing: 8) {
                    if viewModel.backupHealth.needsAttention {
                        BackupHealthRow(health: viewModel.backupHealth) {
                            switch viewModel.backupHealth.status {
                            case .setupNeeded:
                                viewModel.setUpAutomaticBackup()
                            case .pending, .failed:
                                viewModel.retryAutomaticBackup()
                            case .current, .running:
                                break
                            }
                        }
                    }

                    if !viewModel.selectedTagRecords.isEmpty {
                        ExpirySummaryRow(summary: viewModel.selectedTagExpirySummary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()
            }

            List(selection: $viewModel.selectedID) {
                ForEach(viewModel.groupedRecords, id: \.group) { group in
                    Section {
                        ForEach(group.records) { record in
                            CredentialListRow(record: record)
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
                    viewModel.startNew()
                } label: {
                    Label("Add Password", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

private struct BackupHealthRow: View {
    let health: BackupHealth
    let exportAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(health.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(health.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Text(health.detailText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if !health.actionTitle.isEmpty {
                Button {
                    exportAction()
                } label: {
                    Label(health.actionTitle, systemImage: health.actionSystemImage)
                }
                .buttonStyle(.borderless)
                .help(health.actionTitle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
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

    private var updatedText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(record.updatedAt) {
            return "Updated \(record.updatedAt.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.component(.year, from: record.updatedAt) == calendar.component(.year, from: Date()) {
            return "Updated \(record.updatedAt.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return "Updated \(record.updatedAt.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.tint.opacity(0.12))
                Image(systemName: record.totpSecretBase32.isEmpty ? "key.fill" : "lock.rotation")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.headline)
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

                Label(primaryDetail, systemImage: record.username.isEmpty ? "link" : "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    TagPill(text: record.groupName.isEmpty ? "General" : record.groupName, systemImage: "folder")
                        .frame(maxWidth: 118, alignment: .leading)

                    if let expiresAt = record.expiresAt {
                        TagPill(text: expiryText(for: expiresAt), systemImage: "calendar", color: expiryColor(for: expiresAt))
                            .frame(maxWidth: 128, alignment: .leading)
                    }

                    Spacer(minLength: 6)

                    Text(updatedText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .padding(.vertical, 8)
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
        return "Expires \(date.formatted(date: .abbreviated, time: .omitted))"
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

private struct TagPill: View {
    let text: String
    let systemImage: String
    var color: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }
}
