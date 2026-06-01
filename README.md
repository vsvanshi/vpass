# VPass

VPass is a native SwiftUI macOS password vault bootstrap. It stores each full credential record in the user Keychain and keeps only a local UUID index in user defaults.

## Current Features

- Save website/account credentials with username, password, URL, notes, and arbitrary extra fields.
- Store TOTP MFA secrets with each credential.
- Generate live TOTP codes in the detail view.
- Scan `otpauth://totp/...` QR codes from a selected image.
- Scan a QR code visible on the main display using the app's screen capture action.
- Copy username, password, custom fields, and TOTP codes to the clipboard.

## Run Locally

```sh
cd ~/VPass
swift run VPass
```

For normal app development, open `VPass.xcodeproj` in Xcode and run the `VPass` scheme. `Package.swift` is also kept so the source can be built quickly from Terminal.

## Security Notes

- Credential records are serialized as JSON and stored in Keychain generic password items.
- Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- The app does not sync secrets or send data over the network.
- Clipboard copy is intentionally explicit. A future hardening pass should auto-clear copied secrets after a short timeout.
- Screen QR scanning may require granting Screen Recording permission in macOS System Settings.

## App Store Prep

1. Install/select full Xcode, then open `~/VPass/VPass.xcodeproj`.
2. Set the bundle identifier to one you control, for example `com.yourname.vpass`.
3. Add your personal Apple Developer team under Signing & Capabilities.
4. Enable App Sandbox and keep user-selected file read access.
5. Add an app icon asset set before archiving.
6. Archive from Xcode Organizer and upload through App Store Connect.

## Next Good Hardening Steps

- Add app unlock with Touch ID or a local master passphrase gate.
- Clear clipboard after a configurable timeout.
- Add import/export with encrypted backups.
- Add password generation.
- Add item-level history and soft delete.
