import SwiftUI

struct QuickSearchView: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    @State private var query = ""
    @State private var copiedMessage: String?
    @State private var copiedFeedbackID = UUID()

    private var results: [CredentialRecord] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let records = viewModel.records.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        guard !term.isEmpty else {
            return Array(records.prefix(10))
        }

        return records.filter { $0.matchesSearch(term) }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search passwords", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(.regularMaterial)

            Divider()

            if results.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "key", description: Text("Try another search."))
                    .frame(width: 380, height: 220)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { record in
                            QuickCredentialRow(record: record) { label in
                                showCopiedFeedback(label)
                            }
                                .environmentObject(viewModel)
                            if record.id != results.last?.id {
                                Divider()
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
                .frame(width: 420, height: min(CGFloat(results.count) * 78, 420))
            }

            if let copiedMessage {
                Divider()
                Label(copiedMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 420)
        .onAppear {
            viewModel.reload()
        }
    }

    private func showCopiedFeedback(_ label: String) {
        let feedbackID = UUID()
        copiedFeedbackID = feedbackID
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            copiedMessage = "Copied \(label)"
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard copiedFeedbackID == feedbackID else {
                return
            }
            withAnimation(.easeOut(duration: 0.18)) {
                copiedMessage = nil
            }
        }
    }
}

private struct QuickCredentialRow: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    let record: CredentialRecord
    let onCopy: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title.isEmpty ? "Untitled" : record.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.username.isEmpty ? "No username" : record.username)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(record.tag) / \(record.groupName.isEmpty ? "General" : record.groupName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                QuickCopyButton(help: "Copy username", systemImage: "person.text.rectangle") {
                    viewModel.copyToClipboard(record.username, label: "username")
                    onCopy("username")
                }
                .disabled(record.username.isEmpty)

                QuickCopyButton(help: "Copy password", systemImage: "key") {
                    viewModel.copyToClipboard(record.password, label: "password")
                    onCopy("password")
                }
                .disabled(record.password.isEmpty)

                if !record.totpSecretBase32.isEmpty {
                    QuickTOTPButton(record: record) { code in
                        viewModel.copyToClipboard(code, label: "TOTP")
                        onCopy("TOTP")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

}

private struct QuickCopyButton: View {
    let help: String
    let systemImage: String
    let action: () -> Void

    @State private var isShowingSuccess = false

    var body: some View {
        Button {
            action()
            pulse()
        } label: {
            Image(systemName: isShowingSuccess ? "checkmark" : systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isShowingSuccess ? .green : .primary)
                .frame(width: 28, height: 28)
                .background(isShowingSuccess ? Color.green.opacity(0.14) : Color.clear, in: Circle())
                .scaleEffect(isShowingSuccess ? 1.14 : 1)
                .contentShape(Rectangle())
                .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isShowingSuccess)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func pulse() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.58)) {
            isShowingSuccess = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.16)) {
                isShowingSuccess = false
            }
        }
    }
}

private struct QuickTOTPButton: View {
    let record: CredentialRecord
    let onCopy: (String) -> Void

    @State private var isShowingSuccess = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let code = (try? TOTPGenerator.code(
                secretBase32: record.totpSecretBase32,
                date: context.date,
                period: record.totpPeriod,
                digits: record.totpDigits
            )) ?? ""
            let remaining = TOTPGenerator.remainingSeconds(date: context.date, period: record.totpPeriod)

            Button {
                guard !code.isEmpty else {
                    return
                }
                onCopy(code)
                pulse()
            } label: {
                ZStack {
                    Circle()
                        .fill(isShowingSuccess ? Color.green.opacity(0.14) : Color.clear)
                    CountdownRing(
                        remaining: remaining,
                        period: record.totpPeriod,
                        color: isShowingSuccess ? .green : .accentColor
                    )
                    Image(systemName: isShowingSuccess ? "checkmark" : "number")
                        .font(.system(size: isShowingSuccess ? 13 : 11, weight: .semibold))
                        .foregroundStyle(isShowingSuccess ? .green : .primary)
                        .symbolEffect(.bounce, value: isShowingSuccess)
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
                .scaleEffect(isShowingSuccess ? 1.14 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isShowingSuccess)
            }
            .buttonStyle(.plain)
            .help("Copy TOTP, \(remaining)s remaining")
            .disabled(code.isEmpty)
        }
    }

    private func pulse() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.58)) {
            isShowingSuccess = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.16)) {
                isShowingSuccess = false
            }
        }
    }
}

private struct CountdownRing: View {
    let remaining: Int
    let period: Int
    var color: Color = .accentColor

    private var progress: Double {
        guard period > 0 else {
            return 0
        }
        return Double(remaining) / Double(period)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
