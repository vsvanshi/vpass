import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class VaultViewModel: ObservableObject {
    @Published var records: [CredentialRecord] = []
    @Published var selectedID: CredentialRecord.ID?
    @Published var selectedTag = VaultTag.personal.name
    @Published var searchText = ""
    @Published var editor: CredentialDraft?
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published private(set) var isAutomaticBackupRunning = false
    @Published private(set) var automaticBackupErrorMessage: String?
    @Published private(set) var isTOTPSyncEnabled: Bool
    @Published private(set) var lastTOTPSyncAt: Date?
    @Published private(set) var totpSyncErrorMessage: String?

    private let vault: KeychainVault
    private let backupService = BackupService()
    private let backupConfigurationStore: BackupConfigurationStore
    private let totpSyncStore: TOTPKeychainSyncStore
    private let userDefaults: UserDefaults
    private let selectedTagDefaultsKey = "selectedTag"
    private let lastBackupAtDefaultsKey = "lastBackupAt"
    private let lastVaultChangeAtDefaultsKey = "lastVaultChangeAt"
    private let totpSyncEnabledDefaultsKey = "totpSyncEnabled"
    private let lastTOTPSyncAtDefaultsKey = "lastTOTPSyncAt"
    private var automaticBackupTask: Task<Void, Never>?

    init(
        vault: KeychainVault,
        userDefaults: UserDefaults = .standard,
        backupConfigurationStore: BackupConfigurationStore? = nil,
        totpSyncStore: TOTPKeychainSyncStore? = nil
    ) {
        self.vault = vault
        self.userDefaults = userDefaults
        self.backupConfigurationStore = backupConfigurationStore ?? BackupConfigurationStore(userDefaults: userDefaults)
        self.totpSyncStore = totpSyncStore ?? TOTPKeychainSyncStore()
        isTOTPSyncEnabled = userDefaults.bool(forKey: totpSyncEnabledDefaultsKey)
        lastTOTPSyncAt = userDefaults.object(forKey: lastTOTPSyncAtDefaultsKey) as? Date
        let savedTag = userDefaults.string(forKey: selectedTagDefaultsKey) ?? VaultTag.personal.name
        selectedTag = VaultTag.all.contains(where: { $0.name == savedTag }) ? savedTag : VaultTag.personal.name
        reload()
        syncTOTPIfNeeded(showSuccess: false)
    }

    var selectedTagRecords: [CredentialRecord] {
        records.filter { $0.tag == selectedTag }
    }

    var filteredRecords: [CredentialRecord] {
        let tagRecords = selectedTagRecords
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return tagRecords
        }
        return tagRecords.filter { $0.matchesSearch(term) }
    }

    var groupedRecords: [(group: String, records: [CredentialRecord])] {
        let groups = Dictionary(grouping: filteredRecords) { record in
            record.groupName.isEmpty ? "General" : record.groupName
        }
        return groups
            .map { (group: $0.key, records: $0.value.sorted(by: sortRecords)) }
            .sorted { $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedAscending }
    }

    var groupsByTag: [String: [String]] {
        Dictionary(grouping: records, by: \.tag).mapValues { records in
            Array(Set(records.map { $0.groupName.isEmpty ? "General" : $0.groupName }))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    var backupHealth: BackupHealth {
        let lastBackupAt = userDefaults.object(forKey: lastBackupAtDefaultsKey) as? Date
        let lastVaultChangeAt = userDefaults.object(forKey: lastVaultChangeAtDefaultsKey) as? Date
        let destination = try? backupConfigurationStore.loadDestination()
        let currentBackup = destination.map { backupConfigurationStore.backupFileInfo(for: $0.url) }
        let previousBackup = destination.map { backupConfigurationStore.backupFileInfo(for: $0.previousURL) }
        return BackupHealth(
            recordCount: records.count,
            changedRecordCount: records.filter { record in
                guard let lastBackupAt else {
                    return true
                }
                return record.updatedAt > lastBackupAt
            }.count,
            lastBackupAt: lastBackupAt,
            lastVaultChangeAt: lastVaultChangeAt,
            isConfigured: backupConfigurationStore.isConfigured(),
            isRunning: isAutomaticBackupRunning,
            errorMessage: automaticBackupErrorMessage,
            currentBackup: currentBackup,
            previousBackup: previousBackup
        )
    }

    var selectedTagExpirySummary: ExpirySummary {
        ExpirySummary(records: selectedTagRecords)
    }

    var isAutomaticBackupConfigured: Bool {
        backupConfigurationStore.isConfigured()
    }

    var totpSyncCredentialCount: Int {
        records.filter(\.hasTOTP).count
    }

    var lastTOTPSyncText: String {
        guard let lastTOTPSyncAt else {
            return "Never"
        }
        return lastTOTPSyncAt.formatted(date: .abbreviated, time: .shortened)
    }

    var selectedRecord: CredentialRecord? {
        guard let selectedID else {
            return filteredRecords.first
        }
        return records.first { $0.id == selectedID }
    }

    func reload() {
        do {
            records = try vault.loadRecords()
            if !VaultTag.all.contains(where: { $0.name == selectedTag }) {
                setSelectedTag(VaultTag.personal.name, selectFirstRecord: false)
            }
            if let selectedID, records.contains(where: { $0.id == selectedID && $0.tag == selectedTag }) {
                return
            }
            selectedID = filteredRecords.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startNew() {
        var draft = CredentialDraft()
        draft.tag = selectedTag
        draft.groupName = groupedRecords.first?.group ?? "General"
        editor = draft
    }

    func editSelected() {
        guard let selectedRecord else {
            return
        }
        editor = CredentialDraft(record: selectedRecord)
    }

    func saveDraft(_ draft: CredentialDraft) {
        let record = draft.record()
        do {
            try vault.save(record)
            editor = nil
            setSelectedTag(record.tag, selectFirstRecord: false)
            selectedID = record.id
            reload()
            markVaultChanged()
            syncTOTPIfNeeded()
            statusMessage = "Saved \(record.title.isEmpty ? "item" : record.title)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelected() {
        guard let id = selectedRecord?.id else {
            return
        }
        do {
            try vault.delete(id: id)
            selectedID = nil
            reload()
            markVaultChanged()
            syncTOTPIfNeeded()
            statusMessage = "Deleted item."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyToClipboard(_ value: String, label: String) {
        guard !value.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
            statusMessage = "Copied \(label)."
    }

    func selectTag(_ tag: VaultTag) {
        setSelectedTag(tag.name)
    }

    func count(for tag: VaultTag) -> Int {
        records.filter { $0.tag == tag.name }.count
    }

    func exportEncryptedBackup() {
        do {
            let password = try promptForBackupPassword(
                title: "Export Encrypted Backup",
                message: "Choose a backup password. You will need this password to restore your credentials and TOTP secrets.",
                confirmsPassword: true,
                confirmButtonTitle: "Export"
            )
            let backupData = try backupService.export(records: records, password: password)
            guard let destination = chooseBackupExportURL() else {
                return
            }
            try backupData.write(to: destination, options: [.atomic])
            markBackupCompleted()
            statusMessage = "Exported encrypted backup."
            showInfo(title: "Backup Exported", message: "Your encrypted VPass backup was saved.")
        } catch BackupPromptError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setUpAutomaticBackup() {
        do {
            let isChangingPassword = backupConfigurationStore.isConfigured()
            let password = try promptForBackupPassword(
                title: isChangingPassword ? "Change Backup Password" : "Set Up Backup",
                message: isChangingPassword
                    ? "Choose a new backup password. VPass stores it in Keychain and rewrites the latest backup with the new password."
                    : "Choose a backup password. VPass stores it in Keychain and uses it for encrypted recovery backups.",
                confirmsPassword: true,
                confirmButtonTitle: isChangingPassword ? "Change" : "Set Up",
                showsRules: true
            )
            try backupConfigurationStore.saveConfiguration(password: password)
            automaticBackupErrorMessage = nil
            statusMessage = isChangingPassword ? "Backup password changed." : "Backup configured."
            backUpNow()
        } catch BackupPromptError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func backUpNow() {
        guard backupConfigurationStore.isConfigured() else {
            setUpAutomaticBackup()
            return
        }
        runManagedBackupNow()
    }

    func disableAutomaticBackup() {
        guard backupConfigurationStore.isConfigured() else {
            return
        }
        guard confirmDisableAutomaticBackup() else {
            return
        }
        do {
            automaticBackupTask?.cancel()
            try backupConfigurationStore.clear()
            automaticBackupErrorMessage = nil
            isAutomaticBackupRunning = false
            statusMessage = "Automatic backup disabled."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enableTOTPSync() {
        guard !isTOTPSyncEnabled else {
            syncTOTPNow()
            return
        }
        guard confirmEnableTOTPSync() else {
            return
        }

        isTOTPSyncEnabled = true
        userDefaults.set(true, forKey: totpSyncEnabledDefaultsKey)
        syncTOTPIfNeeded()
    }

    func syncTOTPNow() {
        guard isTOTPSyncEnabled else {
            enableTOTPSync()
            return
        }
        syncTOTPIfNeeded()
    }

    func disableTOTPSync() {
        guard isTOTPSyncEnabled else {
            return
        }
        guard confirmDisableTOTPSync() else {
            return
        }

        do {
            try totpSyncStore.clear()
            isTOTPSyncEnabled = false
            lastTOTPSyncAt = nil
            totpSyncErrorMessage = nil
            userDefaults.set(false, forKey: totpSyncEnabledDefaultsKey)
            userDefaults.removeObject(forKey: lastTOTPSyncAtDefaultsKey)
            statusMessage = "iPhone TOTP sync disabled."
        } catch {
            totpSyncErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func importEncryptedBackup() {
        do {
            guard let source = chooseBackupImportURL() else {
                return
            }
            let password = try promptForBackupPassword(
                title: "Import Encrypted Backup",
                message: "Enter the backup password to restore credentials from this file.",
                confirmsPassword: false,
                confirmButtonTitle: "Import",
                showsRules: false
            )
            let backupData = try Data(contentsOf: source)
            let importedRecords = try backupService.import(data: backupData, password: password)

            guard confirmImport(recordCount: importedRecords.count) else {
                return
            }

            for record in importedRecords {
                try vault.save(record)
            }
            reload()
            markVaultChanged()
            syncTOTPIfNeeded()
            statusMessage = "Imported \(importedRecords.count) credential\(importedRecords.count == 1 ? "" : "s")."
            showInfo(
                title: "Backup Imported",
                message: "Imported \(importedRecords.count) credential\(importedRecords.count == 1 ? "" : "s")."
            )
        } catch BackupPromptError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreCurrentBackup() {
        restoreManagedBackup(kind: .current)
    }

    func restorePreviousBackup() {
        restoreManagedBackup(kind: .previous)
    }

    private func restoreManagedBackup(kind: ManagedBackupKind) {
        do {
            let destination = try backupConfigurationStore.loadDestination()
            let url = kind.url(in: destination)
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorMessage = "\(kind.title) was not found."
                return
            }

            let password = try backupConfigurationStore.loadPassword()
            let backupData = try Data(contentsOf: url)
            let importedRecords = try backupService.import(data: backupData, password: password)

            guard confirmRestore(kind: kind, recordCount: importedRecords.count) else {
                return
            }

            for record in importedRecords {
                try vault.save(record)
            }
            reload()
            markVaultChanged()
            syncTOTPIfNeeded()
            statusMessage = "Restored \(importedRecords.count) credential\(importedRecords.count == 1 ? "" : "s")."
            showInfo(
                title: "Backup Restored",
                message: "Added missing credentials and updated matching credentials from \(kind.title.lowercased())."
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sortRecords(_ lhs: CredentialRecord, _ rhs: CredentialRecord) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func setSelectedTag(_ tag: String, selectFirstRecord: Bool = true) {
        selectedTag = tag
        userDefaults.set(tag, forKey: selectedTagDefaultsKey)
        if selectFirstRecord {
            selectedID = filteredRecords.first?.id
        }
    }

    private func markVaultChanged(at date: Date = Date()) {
        userDefaults.set(date, forKey: lastVaultChangeAtDefaultsKey)
        automaticBackupErrorMessage = nil
    }

    private func markBackupCompleted(at date: Date = Date()) {
        userDefaults.set(date, forKey: lastBackupAtDefaultsKey)
    }

    private func syncTOTPIfNeeded(showSuccess: Bool = true) {
        guard isTOTPSyncEnabled else {
            return
        }

        do {
            try totpSyncStore.sync(records: records)
            let syncDate = Date()
            lastTOTPSyncAt = syncDate
            totpSyncErrorMessage = nil
            userDefaults.set(syncDate, forKey: lastTOTPSyncAtDefaultsKey)
            if showSuccess {
                statusMessage = "Synced \(totpSyncCredentialCount) TOTP credential\(totpSyncCredentialCount == 1 ? "" : "s")."
            }
        } catch {
            totpSyncErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func runManagedBackupNow() {
        if isAutomaticBackupRunning {
            return
        }
        automaticBackupTask?.cancel()
        let snapshot = records
        automaticBackupTask = Task { [weak self] in
            await self?.performManagedBackup(records: snapshot)
        }
    }

    private func performManagedBackup(records: [CredentialRecord]) async {
        guard backupConfigurationStore.isConfigured() else {
            return
        }

        do {
            let password = try backupConfigurationStore.loadPassword()
            let destination = try backupConfigurationStore.loadDestination()
            isAutomaticBackupRunning = true
            automaticBackupErrorMessage = nil

            let backupData = try await Task.detached(priority: .utility) {
                try BackupService().export(records: records, password: password)
            }.value

            try writeAutomaticBackup(backupData, to: destination)
            markBackupCompleted()
            isAutomaticBackupRunning = false
            statusMessage = "Backup updated."
        } catch {
            isAutomaticBackupRunning = false
            automaticBackupErrorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func writeAutomaticBackup(_ data: Data, to destination: BackupDestination) throws {
        let url = destination.url
        let directory = destination.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: destination.previousURL)
            try? FileManager.default.copyItem(at: url, to: destination.previousURL)
        }

        try data.write(to: url, options: [.atomic])
    }

    private func chooseBackupExportURL() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Encrypted VPass Backup"
        panel.nameFieldStringValue = defaultBackupFilename()
        if let backupType = UTType(filenameExtension: "vpassbackup") {
            panel.allowedContentTypes = [backupType]
        }
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseBackupImportURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Encrypted VPass Backup"
        if let backupType = UTType(filenameExtension: "vpassbackup") {
            panel.allowedContentTypes = [backupType]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func defaultBackupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "VPass-Backup-\(formatter.string(from: Date())).vpassbackup"
    }

    private func promptForBackupPassword(
        title: String,
        message: String,
        confirmsPassword: Bool,
        confirmButtonTitle: String,
        showsRules: Bool = false
    ) throws -> String {
        let fieldWidth: CGFloat = 320
        let fieldHeight: CGFloat = 24
        let passwordField = BackupPasswordInputRow(
            placeholder: "Backup password",
            fieldWidth: fieldWidth - 36,
            fieldHeight: fieldHeight
        )

        let stackHeight: CGFloat = {
            if confirmsPassword && showsRules {
                return 124
            }
            if confirmsPassword {
                return 86
            }
            return 42
        }()
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: fieldWidth, height: stackHeight))
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.distribution = .fill
        stack.addArrangedSubview(NSTextField(labelWithString: "Backup password"))
        stack.addArrangedSubview(passwordField.view)

        let confirmField: BackupPasswordInputRow?
        if confirmsPassword {
            let field = BackupPasswordInputRow(
                placeholder: "Confirm password",
                fieldWidth: fieldWidth - 36,
                fieldHeight: fieldHeight
            )
            stack.addArrangedSubview(NSTextField(labelWithString: "Confirm password"))
            stack.addArrangedSubview(field.view)
            confirmField = field
        } else {
            confirmField = nil
        }

        if showsRules {
            let rules = NSTextField(wrappingLabelWithString: "Rules: use at least 8 characters. Keep this password safe; older backup files may still need the password used to create them.")
            rules.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            rules.textColor = .secondaryLabelColor
            rules.widthAnchor.constraint(equalToConstant: fieldWidth).isActive = true
            stack.addArrangedSubview(rules)
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.accessoryView = stack
        alert.addButton(withTitle: confirmButtonTitle)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = passwordField.initialFirstResponder

        guard alert.runModal() == .alertFirstButtonReturn else {
            throw BackupPromptError.cancelled
        }

        let password = passwordField.stringValue
        if confirmsPassword, password != confirmField?.stringValue {
            throw BackupPromptError.passwordsDoNotMatch
        }
        guard password.count >= 8 else {
            throw BackupPromptError.passwordTooShort
        }
        return password
    }

    private func confirmImport(recordCount: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Import Backup?"
        alert.informativeText = "This will add or update \(recordCount) credential\(recordCount == 1 ? "" : "s") in your local vault. Existing credentials with the same internal ID will be overwritten."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmRestore(kind: ManagedBackupKind, recordCount: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Restore \(kind.title)?"
        alert.informativeText = "This will add missing credentials and update matching credentials from \(recordCount) backup item\(recordCount == 1 ? "" : "s"). Other current credentials will not be deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmDisableAutomaticBackup() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Disable Automatic Backup?"
        alert.informativeText = "VPass will remove the backup master password from Keychain. Existing backup files will not be deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Disable")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmEnableTOTPSync() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Enable iPhone TOTP Sync?"
        alert.informativeText = "VPass will sync authenticator setup secrets through iCloud Keychain for your future iPhone viewer app. Passwords stay local to this Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmDisableTOTPSync() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Disable iPhone TOTP Sync?"
        alert.informativeText = "VPass will remove synced TOTP viewer items from the shared iCloud Keychain group. Your local vault will not be changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Disable")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private enum BackupPromptError: LocalizedError {
    case cancelled
    case passwordTooShort
    case passwordsDoNotMatch

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return nil
        case .passwordTooShort:
            return "Use at least 8 characters for the backup password."
        case .passwordsDoNotMatch:
            return "The backup passwords do not match."
        }
    }
}

@MainActor
private final class BackupPasswordInputRow: NSObject {
    let view: NSStackView
    let initialFirstResponder: NSView

    private let secureField: NSSecureTextField
    private let plainField: NSTextField
    private let toggleButton: NSButton
    private var isRevealed = false

    init(placeholder: String, fieldWidth: CGFloat, fieldHeight: CGFloat) {
        secureField = NSSecureTextField(frame: .zero)
        secureField.placeholderString = placeholder
        secureField.isBordered = true
        secureField.bezelStyle = .roundedBezel
        secureField.usesSingleLineMode = true

        plainField = NSTextField(frame: .zero)
        plainField.placeholderString = placeholder
        plainField.isBordered = true
        plainField.bezelStyle = .roundedBezel
        plainField.usesSingleLineMode = true
        plainField.isHidden = true

        toggleButton = NSButton(frame: .zero)
        toggleButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Show password")
        toggleButton.bezelStyle = .texturedRounded
        toggleButton.isBordered = false
        toggleButton.setButtonType(.momentaryPushIn)
        toggleButton.toolTip = "Show password"

        let fieldContainer = NSView(frame: .zero)
        [secureField, plainField].forEach { field in
            field.translatesAutoresizingMaskIntoConstraints = false
            fieldContainer.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor),
                field.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
                field.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor)
            ])
        }

        fieldContainer.widthAnchor.constraint(equalToConstant: fieldWidth).isActive = true
        fieldContainer.heightAnchor.constraint(equalToConstant: fieldHeight).isActive = true
        toggleButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        toggleButton.heightAnchor.constraint(equalToConstant: fieldHeight).isActive = true

        view = NSStackView(views: [fieldContainer, toggleButton])
        view.orientation = .horizontal
        view.spacing = 6
        view.alignment = .centerY

        initialFirstResponder = secureField
        super.init()
        toggleButton.target = self
        toggleButton.action = #selector(toggleReveal)
    }

    var stringValue: String {
        get {
            isRevealed ? plainField.stringValue : secureField.stringValue
        }
        set {
            secureField.stringValue = newValue
            plainField.stringValue = newValue
        }
    }

    @objc private func toggleReveal() {
        if isRevealed {
            secureField.stringValue = plainField.stringValue
        } else {
            plainField.stringValue = secureField.stringValue
        }
        isRevealed.toggle()
        secureField.isHidden = isRevealed
        plainField.isHidden = !isRevealed
        toggleButton.image = NSImage(
            systemSymbolName: isRevealed ? "eye.slash" : "eye",
            accessibilityDescription: isRevealed ? "Hide password" : "Show password"
        )
        toggleButton.toolTip = isRevealed ? "Hide password" : "Show password"
        view.window?.makeFirstResponder(isRevealed ? plainField : secureField)
    }
}

private enum ManagedBackupKind {
    case current
    case previous

    var title: String {
        switch self {
        case .current:
            return "Current Backup"
        case .previous:
            return "Previous Backup"
        }
    }

    func url(in destination: BackupDestination) -> URL {
        switch self {
        case .current:
            return destination.url
        case .previous:
            return destination.previousURL
        }
    }
}

struct BackupHealth: Equatable {
    enum Status: Equatable {
        case current
        case setupNeeded
        case pending
        case running
        case failed(String)
    }

    let recordCount: Int
    let changedRecordCount: Int
    let lastBackupAt: Date?
    let lastVaultChangeAt: Date?
    let isConfigured: Bool
    let isRunning: Bool
    let errorMessage: String?
    let currentBackup: BackupFileInfo?
    let previousBackup: BackupFileInfo?

    var status: Status {
        guard recordCount > 0 else {
            return .current
        }
        if let errorMessage {
            return .failed(errorMessage)
        }
        if isRunning {
            return .running
        }
        guard isConfigured else {
            return .setupNeeded
        }
        guard let lastBackupAt else {
            return .pending
        }
        guard let lastVaultChangeAt else {
            return .current
        }
        return lastVaultChangeAt > lastBackupAt ? .pending : .current
    }

    var needsAttention: Bool {
        switch status {
        case .current:
            return false
        case .setupNeeded, .pending, .running, .failed:
            return true
        }
    }

    var title: String {
        switch status {
        case .current:
            return "Backup current"
        case .setupNeeded:
            return "Set up automatic backup"
        case .pending:
            return "Backup pending"
        case .running:
            return "Backing up"
        case .failed:
            return "Backup failed"
        }
    }

    var message: String {
        switch status {
        case .setupNeeded:
            return "VPass keeps current and previous encrypted backups automatically."
        case .failed(let message):
            return message
        case .running:
            return "Updating encrypted backup."
        case .current:
            return lastBackupText
        case .pending:
            if changedRecordCount == 1 {
                return "1 credential changed since your last backup."
            }
            if changedRecordCount > 1 {
                return "\(changedRecordCount) credentials changed since your last backup."
            }
            return "Your vault changed since your last backup."
        }
    }

    var lastBackupText: String {
        guard let lastBackupAt else {
            return "Never backed up"
        }
        return "Last backup \(lastBackupAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var detailText: String {
        if let modifiedAt = currentBackup?.modifiedAt {
            return modifiedAt.formatted(date: .abbreviated, time: .shortened)
        }
        return lastBackupText
    }

    var latestBackupText: String {
        guard let modifiedAt = currentBackup?.modifiedAt else {
            return "No current backup"
        }
        return modifiedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var previousBackupText: String {
        guard let modifiedAt = previousBackup?.modifiedAt else {
            return "No previous backup"
        }
        return modifiedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var hasCurrentBackup: Bool {
        currentBackup?.exists == true
    }

    var hasPreviousBackup: Bool {
        previousBackup?.exists == true
    }

    var actionTitle: String {
        switch status {
        case .setupNeeded:
            return "Set Up"
        case .failed:
            return "Retry"
        case .pending:
            return "Back Up"
        case .running, .current:
            return ""
        }
    }

    var actionSystemImage: String {
        switch status {
        case .setupNeeded:
            return "gearshape"
        case .failed:
            return "arrow.clockwise"
        case .pending:
            return "square.and.arrow.up"
        case .running, .current:
            return "checkmark"
        }
    }
}

struct ExpirySummary: Equatable {
    let total: Int
    let expired: Int
    let expiringSoon: Int
    let withoutExpiry: Int

    init(records: [CredentialRecord], now: Date = Date(), calendar: Calendar = .current) {
        total = records.count
        let today = calendar.startOfDay(for: now)
        let soonLimit = calendar.date(byAdding: .day, value: 30, to: today) ?? today

        var expiredCount = 0
        var expiringSoonCount = 0
        var noExpiryCount = 0

        for record in records {
            guard let expiresAt = record.expiresAt else {
                noExpiryCount += 1
                continue
            }

            let expiryDay = calendar.startOfDay(for: expiresAt)
            if expiryDay < today {
                expiredCount += 1
            } else if expiryDay <= soonLimit {
                expiringSoonCount += 1
            }
        }

        expired = expiredCount
        expiringSoon = expiringSoonCount
        withoutExpiry = noExpiryCount
    }
}
