import SwiftUI
import VPassCore

struct QuickSearchView: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    @EnvironmentObject private var authenticator: AppAuthenticator
    @State private var query = ""
    @State private var copiedMessage: String?
    @State private var copiedFeedbackID = UUID()
    @FocusState private var isSearchFocused: Bool
    @ObservedObject private var context = QuickSearchContext.shared
    /// True in the keyboard-shortcut window: keep the login just used on top.
    /// The menu bar dropdown keeps the plain list;
    /// it sizes itself to its content, and reordering it mid-click crashed
    /// AppKit's window resize.
    var usesShortcutContext = false

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var results: [CredentialRecord] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let records = viewModel.records.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        guard !term.isEmpty else {
            let base = Array(records.prefix(10))
            // Shortcut window: the login whose password was just copied goes
            // on top.
            guard usesShortcutContext else {
                return base
            }
            if let recent = recentRecord {
                return [recent] + base.filter { $0.id != recent.id }
            }
            return base
        }

        return records.filter { $0.matchesSearch(term) }
            .prefix(12)
            .map { $0 }
    }

    private var recentRecord: CredentialRecord? {
        guard usesShortcutContext, let id = context.freshRecentRecordID else {
            return nil
        }
        return viewModel.records.first { $0.id == id }
    }

    /// The login Return / Shift+Return act on: the top search result, or with
    /// an empty search, the login just used.
    private var actionRecord: CredentialRecord? {
        if hasQuery {
            return results.first
        }
        return recentRecord
    }

    var body: some View {
        Group {
            if authenticator.isUnlocked {
                unlockedContent
            } else {
                QuickUnlockView()
                    .environmentObject(authenticator)
            }
        }
        .alert("Unlock Failed", isPresented: Binding(
            get: { authenticator.errorMessage != nil },
            set: { if !$0 { authenticator.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authenticator.errorMessage ?? "")
        }
        .onChange(of: authenticator.isUnlocked) { _, isUnlocked in
            if isUnlocked {
                viewModel.reload()
            }
        }
        .onAppear {
            authenticator.unlockIfRecentlyAuthenticated()
        }
    }

    private var unlockedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search passwords", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        copyTopResult(code: press.modifiers.contains(.shift))
                    }
            }
            .padding(10)
            .background(.regularMaterial)

            if !hasQuery, let recentRecord {
                Text("Continuing with \(recentRecord.title.isEmpty ? recentRecord.username : recentRecord.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            Divider()

            if results.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "key", description: Text("Try another search."))
                    .frame(width: 380, height: 220)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { record in
                            QuickCredentialRow(record: record, isHighlighted: record.id == actionRecord?.id) { label in
                                showCopiedFeedback(label)
                                if label == "password" {
                                    context.rememberPasswordCopy(of: record.id)
                                } else if label == "TOTP" {
                                    context.clearRecent()
                                }
                            }
                                .environmentObject(viewModel)
                            if record.id != results.last?.id {
                                Divider()
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
                // Cap the list height so the tray menu never grows unbounded;
                // beyond this the rows scroll while the search bar (above) and
                // the action buttons (below, in MenuBarRootView) stay fixed.
                .frame(width: 420, height: min(CGFloat(results.count) * 72, 360))
            }

            if actionRecord != nil {
                Divider()
                Text("Return copies password  -  Shift+Return copies 2FA code  -  Ctrl+Option+V opens this anywhere")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
            isSearchFocused = true
        }
        // The panel's view stays alive between openings, so onAppear alone
        // misses reopenings; refocus search whenever a window becomes key.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isSearchFocused = true
        }
        .onReceive(context.$openCount) { _ in
            if usesShortcutContext, context.freshRecentRecordID != nil {
                query = ""
            }
        }
    }

    /// Return / Shift+Return: copy the top result's password or 2FA code,
    /// then close the panel and go back to the previous app for pasting.
    private func copyTopResult(code: Bool) -> KeyPress.Result {
        guard let record = actionRecord else {
            return .ignored
        }
        if code {
            guard record.hasTOTP,
                  let value = try? TOTPGenerator.code(
                    secretBase32: record.totpSecretBase32,
                    period: record.totpPeriod,
                    digits: record.totpDigits
                  ) else {
                showCopiedFeedback("nothing - no 2FA code saved for \(record.title)")
                return .handled
            }
            viewModel.copyToClipboard(value, label: "TOTP", concealed: true)
            context.clearRecent()
        } else {
            guard !record.password.isEmpty else {
                showCopiedFeedback("nothing - no password saved for \(record.title)")
                return .handled
            }
            viewModel.copyToClipboard(record.password, label: "password", concealed: true)
            context.rememberPasswordCopy(of: record.id)
        }
        MenuBarPanel.closeAndReturnFocus()
        return .handled
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

private struct QuickUnlockView: View {
    @EnvironmentObject private var authenticator: AppAuthenticator

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 62, height: 62)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

            VStack(spacing: 4) {
                Text("VPass is Locked")
                    .font(.headline)
                Text("Unlock before searching or copying secrets.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                authenticator.authenticate()
            } label: {
                Label(authenticator.isAuthenticating ? "Unlocking..." : "Unlock", systemImage: "touchid")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .disabled(authenticator.isAuthenticating)
        }
        .padding(24)
        .frame(width: 420, height: 260)
    }
}

private struct QuickCredentialRow: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    let record: CredentialRecord
    /// The row Return / Shift+Return act on.
    var isHighlighted = false
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
                    viewModel.copyToClipboard(record.password, label: "password", concealed: true)
                    onCopy("password")
                }
                .disabled(record.password.isEmpty)

                if !record.totpSecretBase32.isEmpty {
                    QuickTOTPButton(record: record) { code in
                        viewModel.copyToClipboard(code, label: "TOTP", concealed: true)
                        onCopy("TOTP")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)
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
