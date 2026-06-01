# VPass

VPass is a native SwiftUI macOS password manager built for local, personal credential storage. It stores credential records in the user's macOS Keychain, supports TOTP MFA codes, and includes a menu bar quick search for fast copy actions.

## Features

- Store credentials with name, username, password, website, notes, and extra custom fields.
- Organize credentials first by predefined tags: Personal, Work, Finance, and Servers.
- Group credentials inside each tag, such as project names, client names, or social media.
- Reuse existing groups from a dropdown when adding credentials, or create a new group.
- Optional credential expiry date with visual status in the list and detail view.
- Last-updated timestamp on each credential.
- Built-in TOTP generation with configurable period and digit count.
- Scan `otpauth://totp/...` MFA QR codes from an image file.
- Draw a screen capture rectangle around a visible QR code and import the TOTP setup.
- Loose token search in the app and menu bar, so `platform stage` matches `Stage platform core`.
- Menu bar quick search with compact username, password, and TOTP copy buttons.
- Copy feedback and button animation for username, password, and TOTP actions.
- Confirm before deleting a credential.
- Remembers the last selected tag across app launches.

## Security Model

- Credential records are serialized as JSON and stored as Keychain generic password items.
- Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Only a local credential UUID index is stored in user defaults.
- VPass does not sync secrets and does not send vault data over the network.
- Screen Recording permission is used only for the user-triggered QR scan rectangle flow.
- Clipboard copy is explicit. Copied values are not currently auto-cleared.

## Run Locally

Open the Xcode project and run the `VPass` scheme:

```sh
open /Users/varun1/VPass/VPass.xcodeproj
```

You can also run the Swift package target from Terminal:

```sh
cd /Users/varun1/VPass
swift run VPass
```

## Test And Build

Run tests:

```sh
swift test
```

Build without signing for local verification:

```sh
xcodebuild -project VPass.xcodeproj -scheme VPass -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Build the signed Release app:

```sh
xcodebuild -project VPass.xcodeproj -scheme VPass -configuration Release -destination 'platform=macOS' build
```

For local release testing, use the stable app path so macOS privacy permissions stay attached to the same bundle location:

```sh
open /Users/varun1/VPass/Releases/Current/VPass.app
```

## Screen Recording Permission

The screen QR scanner needs macOS Screen Recording permission because it captures the selected screen rectangle. On first scan, macOS shows the normal system permission prompt. After granting permission, quit and reopen VPass from the same app path before scanning again.

## App Store Notes

For Mac App Store distribution:

1. Keep the bundle identifier stable: `com.varunsuryawanshi.vpass`.
2. Use your Apple Developer team in Signing & Capabilities.
3. Keep App Sandbox enabled.
4. Confirm the app icon, version, build number, category, and privacy details.
5. Archive in Xcode and upload through App Store Connect.

Because VPass is local-first, the App Store privacy details should reflect no data collection unless analytics, sync, crash reporting, or network features are added later.

## GitHub Release Notes

For public distribution outside the Mac App Store, publish a Developer ID signed and notarized `.dmg` or `.zip` through GitHub Releases. The normal test build signed with Apple Development is not suitable for public downloads.

Recommended public artifact:

```text
VPass-1.0.0.dmg
```

## Next Hardening Ideas

- Add app unlock with Touch ID or a local master passphrase gate.
- Auto-clear copied secrets after a configurable timeout.
- Add password generation.
- Add encrypted import/export backups.
- Add item history or soft delete.
- Add signed and notarized GitHub release automation.
