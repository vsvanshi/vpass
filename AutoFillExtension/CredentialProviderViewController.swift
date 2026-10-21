import AuthenticationServices
import SwiftUI
import VPassCore

final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var pickerModel: AutoFillModel?

    override func loadView() {
        // No nib: the SwiftUI content is added as a child controller.
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 520))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Touch ID can only be shown once the sheet is on screen.
        pickerModel?.sheetDidAppear()
    }

    // MARK: - Picking from the list

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        showPicker(mode: .password, serviceIdentifiers: serviceIdentifiers, directRecordID: nil)
    }

    @available(macOS 15.0, *)
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        showPicker(mode: .oneTimeCode, serviceIdentifiers: serviceIdentifiers, directRecordID: nil)
    }

    // MARK: - Choosing a suggestion

    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        // Never fill silently: hand back to macOS so it shows our UI, which
        // requires Touch ID or the Mac password before anything is filled.
        extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        showPicker(
            mode: AutoFillMode(requestType: credentialRequest.type),
            serviceIdentifiers: [credentialRequest.credentialIdentity.serviceIdentifier],
            directRecordID: credentialRequest.credentialIdentity.recordIdentifier.flatMap(UUID.init(uuidString:))
        )
    }

    // MARK: - Turning VPass on in System Settings

    override func prepareInterfaceForExtensionConfiguration() {
        show(AutoFillConfigurationView(loadRecords: Self.loadVault) { [weak self] in
            self?.extensionContext.completeExtensionConfigurationRequest()
        })
    }

    // MARK: - Helpers

    /// Reads the shared vault without migrating or deleting anything.
    private static func loadVault() throws -> [CredentialRecord] {
        try KeychainVault().loadCloudRecordsWithoutMigration()
    }

    private func showPicker(mode: AutoFillMode, serviceIdentifiers: [ASCredentialServiceIdentifier], directRecordID: UUID?) {
        let model = AutoFillModel(
            mode: mode,
            serviceIdentifiers: serviceIdentifiers,
            directRecordID: directRecordID,
            loadRecords: Self.loadVault,
            onSelect: { [weak self] record in self?.complete(with: record, mode: mode) },
            onCancel: { [weak self] error in self?.cancel(error) }
        )
        pickerModel = model
        show(AutoFillPickerView(model: model))
    }

    private func complete(with record: CredentialRecord, mode: AutoFillMode) {
        switch mode {
        case .password:
            let credential = ASPasswordCredential(user: record.username, password: record.password)
            extensionContext.completeRequest(withSelectedCredential: credential, completionHandler: nil)
        case .oneTimeCode:
            guard #available(macOS 15.0, *),
                  let code = try? TOTPGenerator.code(
                    secretBase32: record.totpSecretBase32,
                    period: record.totpPeriod,
                    digits: record.totpDigits
                  ) else {
                cancel(.failed)
                return
            }
            extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: code), completionHandler: nil)
        }
    }

    private func cancel(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: ASExtensionError(code))
    }

    private func show<Content: View>(_ content: Content) {
        children.forEach { child in
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        let host = NSHostingController(rootView: content)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
