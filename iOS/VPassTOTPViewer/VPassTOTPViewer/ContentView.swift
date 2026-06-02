import SwiftUI

@MainActor
final class VaultListViewModel: ObservableObject {
    @Published private(set) var records: [CredentialRecord] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastLoadedAt: Date?
    @Published var searchText = ""
    @Published var selectedTag = VaultTag.personal.name
    @Published var editor: CredentialDraft?

    private let store = VaultKeychainStore()

    var filteredRecords: [CredentialRecord] {
        records
            .filter { $0.tag == selectedTag }
            .filter { $0.matches(searchText) }
    }

    var groupedRecords: [(String, [CredentialRecord])] {
        Dictionary(grouping: filteredRecords, by: \.displayGroup)
            .map { ($0.key, $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    var groupsByTag: [String: [String]] {
        Dictionary(grouping: records, by: \.tag).mapValues { records in
            Array(Set(records.map(\.displayGroup)))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    func load() {
        do {
            records = try store.loadRecords()
            errorMessage = nil
            lastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startNew() {
        var draft = CredentialDraft()
        draft.tag = selectedTag
        draft.groupName = groupsByTag[selectedTag]?.first ?? "General"
        editor = draft
    }

    func edit(_ record: CredentialRecord) {
        editor = CredentialDraft(record: record)
    }

    func save(_ draft: CredentialDraft) {
        do {
            let record = draft.record()
            try store.save(record)
            selectedTag = record.tag
            editor = nil
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ record: CredentialRecord) {
        do {
            try store.delete(id: record.id)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = VaultListViewModel()
    @StateObject private var authenticator = AppAuthenticator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if authenticator.isUnlocked {
                vaultContent
            } else {
                LockedVaultView()
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                authenticator.unlockIfRecentlyAuthenticated()
            } else {
                authenticator.lock()
            }
        }
        .onAppear {
            authenticator.unlockIfRecentlyAuthenticated()
        }
    }

    private var vaultContent: some View {
        NavigationStack {
            Group {
                if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Could Not Load", systemImage: "key.icloud")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            viewModel.load()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if viewModel.records.isEmpty {
                    ContentUnavailableView {
                        Label("No Credentials", systemImage: "lock.shield")
                    } description: {
                        Text("Add a credential here or from VPass on your Mac.")
                    } actions: {
                        Button("Add Credential") {
                            viewModel.startNew()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            Picker("Tag", selection: $viewModel.selectedTag) {
                                ForEach(VaultTag.all) { tag in
                                    Label(tag.name, systemImage: tag.systemImage)
                                        .tag(tag.name)
                                }
                            }
                            .pickerStyle(.segmented)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        }

                        ForEach(viewModel.groupedRecords, id: \.0) { title, records in
                            Section(title) {
                                ForEach(records) { record in
                                    NavigationLink {
                                        CredentialDetailView(
                                            record: record,
                                            onEdit: { viewModel.edit(record) },
                                            onDelete: { viewModel.delete(record) }
                                        )
                                    } label: {
                                        CredentialRowView(record: record)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .overlay {
                        if viewModel.filteredRecords.isEmpty {
                            ContentUnavailableView.search(text: viewModel.searchText)
                        }
                    }
                }
            }
            .navigationTitle("VPass")
            .searchable(text: $viewModel.searchText, prompt: "Search credentials")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.startNew()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Credential")
                }
            }
        }
        .sheet(item: $viewModel.editor) { draft in
            CredentialEditorView(
                initialDraft: draft,
                groupsByTag: viewModel.groupsByTag,
                onSave: viewModel.save,
                onCancel: { viewModel.editor = nil }
            )
        }
        .onAppear {
            viewModel.load()
        }
    }
}

private struct LockedVaultView: View {
    @EnvironmentObject private var authenticator: AppAuthenticator

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 92, height: 92)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))

            VStack(spacing: 7) {
                Text("VPass is Locked")
                    .font(.title2.weight(.semibold))
                Text("Use Face ID, Touch ID, or your passcode to unlock your vault.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                authenticator.authenticate()
            } label: {
                Label(authenticator.isAuthenticating ? "Unlocking..." : "Unlock VPass", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(authenticator.isAuthenticating)
            .padding(.horizontal, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct CredentialRowView: View {
    let record: CredentialRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.hasTOTP ? "lock.rotation" : "key.fill")
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title.isEmpty ? "Untitled" : record.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.username.isEmpty ? record.displayGroup : record.username)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if record.hasTOTP {
                Image(systemName: "number.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CredentialDetailView: View {
    let record: CredentialRecord
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var copiedValue: String?
    @State private var revealPassword = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                LabeledContent("Username") {
                    CopyButton(text: record.username, label: "Username", copiedValue: $copiedValue)
                }
                LabeledContent("Password") {
                    HStack {
                        Text(revealPassword ? record.password : String(repeating: "•", count: min(max(record.password.count, 8), 12)))
                            .font(.system(.body, design: .monospaced))
                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        CopyButton(text: record.password, label: "Password", copiedValue: $copiedValue)
                    }
                }
                if !record.url.isEmpty {
                    LabeledContent("Website", value: record.url)
                }
                LabeledContent("Group", value: "\(record.tag) / \(record.displayGroup)")
                LabeledContent("Updated", value: record.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if record.hasTOTP {
                Section("Authenticator") {
                    TOTPCodeView(record: record, copiedValue: $copiedValue)
                    LabeledContent("Issuer", value: record.totpIssuer)
                    LabeledContent("Account", value: record.totpAccount)
                }
            }

            if !record.customFields.isEmpty {
                Section("Extra Information") {
                    ForEach(record.customFields) { field in
                        LabeledContent(field.key) {
                            if field.isSensitive {
                                CopyButton(text: field.value, label: field.key, copiedValue: $copiedValue)
                            } else {
                                Text(field.value)
                            }
                        }
                    }
                }
            }

            if !record.notes.isEmpty {
                Section("Notes") {
                    Text(record.notes)
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Credential", systemImage: "trash")
                }
            }
        }
        .navigationTitle(record.title.isEmpty ? "Credential" : record.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: onEdit)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let copiedValue {
                Label("\(copiedValue) copied", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .alert("Delete Credential?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the credential from synced iCloud Keychain on your devices.")
        }
    }
}

private struct TOTPCodeView: View {
    let record: CredentialRecord
    @Binding var copiedValue: String?

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let code = (try? TOTPGenerator.code(
                secretBase32: record.totpSecretBase32,
                date: context.date,
                period: record.totpPeriod,
                digits: record.totpDigits
            )) ?? String(repeating: "-", count: max(record.totpDigits, 6))
            let remaining = TOTPGenerator.remainingSeconds(date: context.date, period: record.totpPeriod)
            let progress = Double(remaining) / Double(max(record.totpPeriod, 1))

            HStack {
                Text(code)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                CircularCountdown(progress: progress, remaining: remaining)
                Spacer()
                CopyButton(text: code, label: "TOTP", copiedValue: $copiedValue)
            }
        }
    }
}

private struct CredentialEditorView: View {
    @State private var draft: CredentialDraft
    @State private var groupMode: GroupMode
    @State private var newGroupName: String
    @State private var revealPassword = false
    @State private var showsScanner = false
    @State private var errorMessage: String?

    let groupsByTag: [String: [String]]
    let onSave: (CredentialDraft) -> Void
    let onCancel: () -> Void

    init(
        initialDraft: CredentialDraft,
        groupsByTag: [String: [String]],
        onSave: @escaping (CredentialDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let groups = groupsByTag[initialDraft.tag] ?? []
        let hasGroup = groups.contains { $0.caseInsensitiveCompare(initialDraft.groupName) == .orderedSame }
        _draft = State(initialValue: initialDraft)
        _groupMode = State(initialValue: hasGroup ? .existing : .new)
        _newGroupName = State(initialValue: hasGroup ? "" : initialDraft.groupName)
        self.groupsByTag = groupsByTag
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Organization") {
                    Picker("Tag", selection: $draft.tag) {
                        ForEach(VaultTag.all) { tag in
                            Label(tag.name, systemImage: tag.systemImage)
                                .tag(tag.name)
                        }
                    }
                    Picker("Group", selection: $groupMode) {
                        Text("Existing").tag(GroupMode.existing)
                        Text("New").tag(GroupMode.new)
                    }
                    .pickerStyle(.segmented)

                    if groupMode == .existing {
                        Picker("Existing Group", selection: $draft.groupName) {
                            if availableGroups.isEmpty {
                                Text("General").tag("General")
                            } else {
                                ForEach(availableGroups, id: \.self) { group in
                                    Text(group).tag(group)
                                }
                            }
                        }
                    } else {
                        TextField("New Group", text: $newGroupName)
                            .onChange(of: newGroupName) { _, value in
                                draft.groupName = value
                            }
                    }
                }

                Section("Account") {
                    TextField("Name", text: $draft.title)
                    TextField("Username", text: $draft.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Group {
                            if revealPassword {
                                TextField("Password", text: $draft.password)
                            } else {
                                SecureField("Password", text: $draft.password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                        }
                    }
                    TextField("Website", text: $draft.url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Toggle("Has expiry date", isOn: $draft.hasExpiry)
                    if draft.hasExpiry {
                        DatePicker("Expires", selection: $draft.expiresAt, displayedComponents: [.date])
                    }
                }

                Section("Authenticator") {
                    TextField("Issuer", text: $draft.totpIssuer)
                    TextField("Account", text: $draft.totpAccount)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("TOTP Secret", text: $draft.totpSecretBase32)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Stepper("Period: \(draft.totpPeriod)s", value: $draft.totpPeriod, in: 10...120, step: 5)
                    Stepper("Digits: \(draft.totpDigits)", value: $draft.totpDigits, in: 6...8)
                    Button {
                        showsScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                }

                Section("Extra Information") {
                    ForEach($draft.customFields) { $field in
                        VStack(alignment: .leading) {
                            TextField("Field", text: $field.key)
                            if field.isSensitive {
                                SecureField("Value", text: $field.value)
                            } else {
                                TextField("Value", text: $field.value)
                            }
                            Toggle("Sensitive", isOn: $field.isSensitive)
                        }
                    }
                    .onDelete { offsets in
                        draft.customFields.remove(atOffsets: offsets)
                    }
                    Button {
                        draft.customFields.append(CustomField())
                    } label: {
                        Label("Add Field", systemImage: "plus")
                    }
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 88)
                }
            }
            .navigationTitle(draft.title.isEmpty ? "Credential" : draft.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onChange(of: draft.tag) { _, _ in
            if groupMode == .existing {
                draft.groupName = availableGroups.first ?? "General"
            }
        }
        .onChange(of: groupMode) { _, mode in
            switch mode {
            case .existing:
                draft.groupName = availableGroups.first ?? "General"
            case .new:
                newGroupName = ""
                draft.groupName = ""
            }
        }
        .fullScreenCover(isPresented: $showsScanner) {
            NavigationStack {
                QRCodeScannerView { payload in
                    showsScanner = false
                    do {
                        try applyOTPAuth(payload)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } onError: { message in
                    showsScanner = false
                    errorMessage = message
                }
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showsScanner = false
                        }
                    }
                }
            }
        }
        .alert("QR Scan Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var availableGroups: [String] {
        groupsByTag[draft.tag] ?? []
    }

    private func applyOTPAuth(_ payload: String) throws {
        let config = try OTPAuthParser.parse(payload)
        draft.totpSecretBase32 = config.secret
        draft.totpIssuer = config.issuer
        draft.totpAccount = config.account
        draft.totpPeriod = config.period
        draft.totpDigits = config.digits

        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.title = config.issuer.isEmpty ? config.account : config.issuer
        }
        if draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.username = config.account
        }
    }
}

private enum GroupMode: Hashable {
    case existing
    case new
}

private struct CopyButton: View {
    let text: String
    let label: String
    @Binding var copiedValue: String?

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            withAnimation(.snappy(duration: 0.18)) {
                copiedValue = label
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.snappy(duration: 0.18)) {
                    if copiedValue == label {
                        copiedValue = nil
                    }
                }
            }
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .disabled(text.isEmpty)
    }
}

private struct CircularCountdown: View {
    let progress: Double
    let remaining: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(remaining)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 28, height: 28)
    }
}
