import AuthenticationServices
import SwiftUI
import VPassCore

final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var pickerModel: AutoFillModel?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Face ID can only be shown once the sheet is on screen; asking from
        // SwiftUI's onAppear fails with "User interaction required".
        pickerModel?.sheetDidAppear()
    }

    // MARK: - Picking from the list

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        showPicker(mode: .password, serviceIdentifiers: serviceIdentifiers)
    }

    @available(iOS 18.0, *)
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        showPicker(mode: .oneTimeCode, serviceIdentifiers: serviceIdentifiers)
    }

    // MARK: - Tapping a suggestion above the keyboard

    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        // Never fill silently: hand back to iOS so it shows our UI, which
        // requires Face ID before anything is filled.
        extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        let mode = AutoFillMode(requestType: credentialRequest.type)
        let recordID = credentialRequest.credentialIdentity.recordIdentifier.flatMap(UUID.init(uuidString:))
        let model = AutoFillModel(
            mode: mode,
            serviceIdentifiers: [credentialRequest.credentialIdentity.serviceIdentifier],
            directRecordID: recordID,
            loadRecords: { try VaultKeychainStore().loadRecords() },
            onSelect: { [weak self] record in self?.complete(with: record, mode: mode) },
            onCancel: { [weak self] error in self?.cancel(error) }
        )
        pickerModel = model
        show(AutoFillPickerView(model: model))
    }

    // MARK: - Turning VPass on in Settings

    override func prepareInterfaceForExtensionConfiguration() {
        show(AutoFillConfigurationView { [weak self] in
            self?.extensionContext.completeExtensionConfigurationRequest()
        })
    }

    // MARK: - Helpers

    private func showPicker(mode: AutoFillMode, serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        let model = AutoFillModel(
            mode: mode,
            serviceIdentifiers: serviceIdentifiers,
            directRecordID: nil,
            loadRecords: { try VaultKeychainStore().loadRecords() },
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
            guard #available(iOS 18.0, *),
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
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        let host = UIHostingController(rootView: content)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}
