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
        .navigationTitle(viewModel.selectedTag)
        .searchable(text: $viewModel.searchText, placement: .toolbar)
        .overlay {
            if viewModel.selectedTagRecords.isEmpty {
                ContentUnavailableView("No \(viewModel.selectedTag) Passwords", systemImage: "folder", description: Text("Add your first credential here."))
            } else if viewModel.filteredRecords.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            }
        }
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
        record.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.tint.opacity(0.12))
                Image(systemName: record.totpSecretBase32.isEmpty ? "key.fill" : "lock.rotation")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.headline)
                        .lineLimit(1)

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

                HStack(spacing: 6) {
                    TagPill(text: record.groupName.isEmpty ? "General" : record.groupName, systemImage: "folder")

                    if let expiresAt = record.expiresAt {
                        TagPill(text: expiryText(for: expiresAt), systemImage: "calendar", color: expiryColor(for: expiresAt))
                    }
                }
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("Updated")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                Text(updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(width: 86, alignment: .trailing)
            }
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
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }
}
