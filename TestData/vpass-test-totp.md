# VPass Test TOTP

Use this disposable authenticator QR to test VPass scanning and iPhone TOTP sync.

QR image:

`TestData/vpass-test-totp-qr.png`

Payload:

```text
otpauth://totp/VPass%20Test:sync-test@vpass.local?secret=JBSWY3DPEHPK3PXP&issuer=VPass%20Test&period=30&digits=6
```

Manual values:

```text
Issuer: VPass Test
Account: sync-test@vpass.local
Secret: JBSWY3DPEHPK3PXP
Period: 30
Digits: 6
```

Suggested test:

1. Open `TestData/vpass-test-totp-qr.png`.
2. In VPass, add a credential and scan the QR from the screen.
3. Save the credential.
4. Enable iPhone TOTP Sync in Settings, then click Sync Now.
5. Open the iOS viewer on the same iCloud account and refresh.
