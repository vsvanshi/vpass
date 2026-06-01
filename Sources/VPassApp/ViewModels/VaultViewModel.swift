import AppKit
import Foundation

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
}
