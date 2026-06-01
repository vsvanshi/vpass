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

    private let vault: KeychainVault
    private let backupService = BackupService()
    private let userDefaults: UserDefaults
    private let selectedTagDefaultsKey = "selectedTag"

    init(vault: KeychainVault, userDefaults: UserDefaults = .standard) {
        self.vault = vault
        self.userDefaults = userDefaults
        let savedTag = userDefaults.string(forKey: selectedTagDefaultsKey) ?? VaultTag.personal.name
        selectedTag = VaultTag.all.contains(where: { $0.name == savedTag }) ? savedTag : VaultTag.personal.name
        reload()
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
                confirmsPassword: true
            )
            let backupData = try backupService.export(records: records, password: password)
            guard let destination = chooseBackupExportURL() else {
                return
            }
            try backupData.write(to: destination, options: [.atomic])
            statusMessage = "Exported encrypted backup."
            showInfo(title: "Backup Exported", message: "Your encrypted VPass backup was saved.")
        } catch BackupPromptError.cancelled {
        } catch {
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
                confirmsPassword: false
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
        confirmsPassword: Bool
    ) throws -> String {
        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        passwordField.placeholderString = "Backup password"

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.addArrangedSubview(passwordField)

        let confirmField: NSSecureTextField?
        if confirmsPassword {
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.placeholderString = "Confirm password"
            stack.addArrangedSubview(field)
            confirmField = field
        } else {
            confirmField = nil
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.accessoryView = stack
        alert.addButton(withTitle: confirmsPassword ? "Export" : "Import")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = passwordField

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
