import SwiftUI

struct CredentialEditorView: View {
    @State private var draft: CredentialDraft
    @State private var groupMode: GroupMode
    @State private var newGroupName: String
    @State private var revealPassword = false
    @State private var errorMessage: String?
    @State private var expiryShortcutValue = 30
    @State private var expiryShortcutUnit = ExpiryShortcutUnit.days

    let groupsByTag: [String: [String]]
    let onSave: (CredentialDraft) -> Void
    let onCancel: () -> Void

    init(
        initialDraft: CredentialDraft,
        groupsByTag: [String: [String]],
        onSave: @escaping (CredentialDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let initialGroups = groupsByTag[initialDraft.tag] ?? []
        let hasInitialGroup = initialGroups.contains { $0.caseInsensitiveCompare(initialDraft.groupName) == .orderedSame }
        _draft = State(initialValue: initialDraft)
        _groupMode = State(initialValue: hasInitialGroup ? .existing : .new)
        _newGroupName = State(initialValue: hasInitialGroup ? "" : initialDraft.groupName)
        self.groupsByTag = groupsByTag
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
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
                        ExistingGroupPicker(
                            groups: availableGroups,
                            selectedGroup: $draft.groupName
                        )
                    } else {
                        TextField("New group name", text: $newGroupName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: newGroupName) { _, value in
                                draft.groupName = value
                            }
                    }
                }

                Section("Account") {
                    TextField("Name", text: $draft.title)
                    TextField("Username", text: $draft.username)
                    passwordField
                    TextField("Website", text: $draft.url)
                    Toggle("Has expiry date", isOn: $draft.hasExpiry)
                        .toggleStyle(.checkbox)
                    if draft.hasExpiry {
                        DatePicker(
                            "Expires",
                            selection: $draft.expiresAt,
                            displayedComponents: [.date]
                        )
                        ExpiryShortcutControl(
                            value: $expiryShortcutValue,
                            unit: $expiryShortcutUnit
                        ) {
                            applyExpiryShortcut()
                        }
                    }
                }

                Section("Authenticator") {
                    TextField("Issuer", text: $draft.totpIssuer)
                    TextField("Account", text: $draft.totpAccount)
                    SecureField("TOTP secret", text: $draft.totpSecretBase32)
                    HStack {
                        Stepper("Period: \(draft.totpPeriod)s", value: $draft.totpPeriod, in: 10...120, step: 5)
                        Stepper("Digits: \(draft.totpDigits)", value: $draft.totpDigits, in: 6...8)
                    }
                    Button {
                        scanFromImage()
                    } label: {
                        Label("Choose QR Image", systemImage: "photo")
                    }
                    if !draft.totpSecretBase32.isEmpty,
                       let code = try? TOTPGenerator.code(secretBase32: draft.totpSecretBase32, period: draft.totpPeriod, digits: draft.totpDigits) {
                        Text("Current code: \(code)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Extra Information") {
                    ForEach($draft.customFields) { $field in
                        HStack {
                            TextField("Field", text: $field.key)
                            if field.isSensitive {
                                SecureField("Value", text: $field.value)
                            } else {
                                TextField("Value", text: $field.value)
                            }
                            Toggle("Sensitive", isOn: $field.isSensitive)
                                .toggleStyle(.checkbox)
                            Button {
                                draft.customFields.removeAll { $0.id == field.id }
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    Button {
                        draft.customFields.append(CustomField())
                    } label: {
                        Label("Add Field", systemImage: "plus")
                    }
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 92)
                        .font(.body)
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                Spacer()
                Button("Save") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(maxWidth: 760, maxHeight: .infinity)
        .onChange(of: draft.tag) { _, _ in
            if groupMode == .existing {
                let firstGroup = availableGroups.first ?? "General"
                draft.groupName = firstGroup
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
        .alert("QR Scan Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var passwordField: some View {
        HStack {
            Group {
                if revealPassword {
                    TextField("Password", text: $draft.password)
                } else {
                    SecureField("Password", text: $draft.password)
                }
            }
            Toggle(isOn: $revealPassword) {
                Label("Reveal Password", systemImage: revealPassword ? "eye.slash" : "eye")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
        }
    }

    private var availableGroups: [String] {
        groupsByTag[draft.tag] ?? []
    }

    private func applyExpiryShortcut() {
        let today = Calendar.current.startOfDay(for: Date())
        draft.expiresAt = Calendar.current.date(
            byAdding: expiryShortcutUnit.calendarComponent,
            value: expiryShortcutValue,
            to: today
        ) ?? draft.expiresAt
    }

    @MainActor
    private func scanFromImage() {
        do {
            let payload = try QRCodeScanner.scanImageFromDisk()
            try applyOTPAuth(payload)
        } catch QRCodeScannerError.noImageSelected {
        } catch {
            errorMessage = error.localizedDescription
        }
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

private enum ExpiryShortcutUnit: String, CaseIterable, Identifiable {
    case days = "Days"
    case months = "Months"

    var id: Self { self }

    var calendarComponent: Calendar.Component {
        switch self {
        case .days:
            .day
        case .months:
            .month
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .days:
            1...730
        case .months:
            1...60
        }
    }
}

private struct ExpiryShortcutControl: View {
    @Binding var value: Int
    @Binding var unit: ExpiryShortcutUnit
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("From now", systemImage: "calendar.badge.clock")
                .foregroundStyle(.secondary)

            Picker("Unit", selection: $unit) {
                ForEach(ExpiryShortcutUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 170)
            .onChange(of: unit) { _, newUnit in
                value = min(max(value, newUnit.range.lowerBound), newUnit.range.upperBound)
            }

            Stepper(value: $value, in: unit.range) {
                Text("\(value)")
                    .monospacedDigit()
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .frame(width: 120)

            Button {
                onApply()
            } label: {
                Label("Set expiry", systemImage: "calendar.badge.checkmark")
            }
        }
    }
}

private struct ExistingGroupPicker: View {
    let groups: [String]
    @Binding var selectedGroup: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Existing group", selection: $selectedGroup) {
                if groups.isEmpty {
                    Text("No groups yet").tag("")
                } else {
                    ForEach(groups, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }
            }
            .disabled(groups.isEmpty)

            if groups.isEmpty {
                Text("Switch to New to create the first group for this tag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
