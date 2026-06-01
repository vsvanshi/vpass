import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    @State private var showingDeleteConfirmation = false
    let record: CredentialRecord?

    var body: some View {
        Group {
            if let record {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header(record)
                        if let expiresAt = record.expiresAt {
                            expiryPanel(expiresAt)
                        }
                        credentialRows(record)
                        if !record.totpSecretBase32.isEmpty {
                            totpPanel(record)
                        }
                        if !record.customFields.isEmpty {
                            customFields(record)
                        }
                        if !record.notes.isEmpty {
                            notes(record)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 760, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select a Password", systemImage: "lock.shield", description: Text("Your saved credentials will appear here."))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.editSelected()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(record == nil)

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(record == nil)
            }
        }
        .alert("Delete Credential?", isPresented: $showingDeleteConfirmation, presenting: record) { _ in
            Button("Delete", role: .destructive) {
                viewModel.deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: { record in
            Text("This will permanently delete \(record.title.isEmpty ? "this credential" : record.title).")
        }
    }

    private func header(_ record: CredentialRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(record.tag)
                Text(record.groupName.isEmpty ? "General" : record.groupName)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            Text(record.title.isEmpty ? "Untitled" : record.title)
                .font(.largeTitle.bold())
            if !record.url.isEmpty {
                Link(record.url, destination: URL(string: record.url.hasPrefix("http") ? record.url : "https://\(record.url)")!)
                    .font(.callout)
            }
            Label("Last updated \(record.updatedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func expiryPanel(_ expiresAt: Date) -> some View {
        let status = ExpiryStatus(date: expiresAt)
        return HStack(spacing: 10) {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.headline)
                Text(status.subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(expiresAt, format: .dateTime.day().month().year())
                .font(.callout.weight(.medium))
                .foregroundStyle(status.color)
        }
        .padding(14)
        .background(status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func credentialRows(_ record: CredentialRecord) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
            row("Username", value: record.username, copyLabel: "username")
            row("Password", value: record.password.isEmpty ? "" : String(repeating: "•", count: 12), copyValue: record.password, copyLabel: "password")
        }
    }

    private func row(_ title: String, value: String, copyValue: String? = nil, copyLabel: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "Not set" : value)
                .textSelection(.enabled)
                .monospaced(value != "Not set")
            Button {
                viewModel.copyToClipboard(copyValue ?? value, label: copyLabel)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled((copyValue ?? value).isEmpty)
        }
    }

    private func totpPanel(_ record: CredentialRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Authenticator")
                .font(.headline)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let code = (try? TOTPGenerator.code(
                    secretBase32: record.totpSecretBase32,
                    date: context.date,
                    period: record.totpPeriod,
                    digits: record.totpDigits
                )) ?? "------"
                let remaining = TOTPGenerator.remainingSeconds(date: context.date, period: record.totpPeriod)

                HStack(spacing: 18) {
                    Text(code)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    ProgressView(value: Double(remaining), total: Double(max(record.totpPeriod, 1)))
                        .frame(width: 120)
                    Text("\(remaining)s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button {
                        viewModel.copyToClipboard(code, label: "TOTP")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
            if !record.totpIssuer.isEmpty || !record.totpAccount.isEmpty {
                Text([record.totpIssuer, record.totpAccount].filter { !$0.isEmpty }.joined(separator: " / "))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func customFields(_ record: CredentialRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extra Information")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                ForEach(record.customFields) { field in
                    row(
                        field.key,
                        value: field.isSensitive ? String(repeating: "•", count: 10) : field.value,
                        copyValue: field.value,
                        copyLabel: field.key
                    )
                }
            }
        }
    }

    private func notes(_ record: CredentialRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            Text(record.notes)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ExpiryStatus {
    let date: Date

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var daysRemaining: Int {
        Calendar.current.dateComponents(
            [.day],
            from: startOfToday,
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
    }

    var title: String {
        if daysRemaining < 0 {
            return "Expired"
        }
        if daysRemaining == 0 {
            return "Expires today"
        }
        if daysRemaining <= 30 {
            return "Expiring soon"
        }
        return "Expiry date"
    }

    var subtitle: String {
        if daysRemaining < 0 {
            return "Expired \(abs(daysRemaining)) day\(abs(daysRemaining) == 1 ? "" : "s") ago"
        }
        if daysRemaining == 0 {
            return "Rotate this credential today"
        }
        return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining"
    }

    var systemImage: String {
        daysRemaining <= 30 ? "calendar.badge.exclamationmark" : "calendar"
    }

    var color: Color {
        if daysRemaining < 0 {
            return .red
        }
        if daysRemaining <= 30 {
            return .orange
        }
        return .green
    }
}
