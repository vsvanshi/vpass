import CryptoKit
import Foundation
import Security

enum BackupError: LocalizedError {
    case emptyPassword
    case invalidFormat
    case unsupportedVersion(Int)
    case encryptionFailed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            return "Enter a backup password."
        case .invalidFormat:
            return "This backup file is not valid."
        case .unsupportedVersion(let version):
            return "This backup version is not supported: \(version)."
        case .encryptionFailed:
            return "The backup could not be encrypted."
        case .decryptionFailed:
            return "The backup password is incorrect, or the file is damaged."
        }
    }
}

struct BackupService {
    private static let currentVersion = 1
    private static let kdfName = "pbkdf2-hmac-sha256"
    private static let iterations = 210_000
    private static let saltBytes = 16

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func export(records: [CredentialRecord], password: String) throws -> Data {
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPassword.isEmpty else {
            throw BackupError.emptyPassword
        }

        let payload = BackupPayload(exportedAt: Date(), records: records)
        let payloadData = try encoder.encode(payload)
        let salt = randomData(count: Self.saltBytes)
        let key = try deriveKey(password: normalizedPassword, salt: salt, iterations: Self.iterations)
        let sealedBox = try AES.GCM.seal(payloadData, using: key)

        guard let ciphertext = sealedBox.ciphertext.base64EncodedString().nilIfEmpty,
              let tag = sealedBox.tag.base64EncodedString().nilIfEmpty else {
            throw BackupError.encryptionFailed
        }

        let file = BackupFile(
            version: Self.currentVersion,
            app: "VPass",
            createdAt: Date(),
            kdf: Self.kdfName,
            iterations: Self.iterations,
            salt: salt.base64EncodedString(),
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0).base64EncodedString() },
            ciphertext: ciphertext,
            tag: tag
        )
        return try encoder.encode(file)
    }

    func `import`(data: Data, password: String) throws -> [CredentialRecord] {
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPassword.isEmpty else {
            throw BackupError.emptyPassword
        }

        let file = try decoder.decode(BackupFile.self, from: data)
        guard file.version == Self.currentVersion else {
            throw BackupError.unsupportedVersion(file.version)
        }
        guard file.kdf == Self.kdfName,
              let salt = Data(base64Encoded: file.salt),
              let nonceData = Data(base64Encoded: file.nonce),
              let ciphertext = Data(base64Encoded: file.ciphertext),
              let tag = Data(base64Encoded: file.tag) else {
            throw BackupError.invalidFormat
        }

        let key = try deriveKey(password: normalizedPassword, salt: salt, iterations: file.iterations)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let payloadData = try AES.GCM.open(sealedBox, using: key)
            let payload = try decoder.decode(BackupPayload.self, from: payloadData)
            return payload.records
        } catch {
            throw BackupError.decryptionFailed
        }
    }

    private func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8), iterations > 0 else {
            throw BackupError.invalidFormat
        }
        let keyData = pbkdf2SHA256(password: passwordData, salt: salt, iterations: iterations, keyByteCount: 32)
        return SymmetricKey(data: keyData)
    }

    private func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, keyByteCount: Int) -> Data {
        let hashByteCount = 32
        let blockCount = Int(ceil(Double(keyByteCount) / Double(hashByteCount)))
        var derived = Data()

        for blockIndex in 1...blockCount {
            var blockSalt = salt
            blockSalt.append(UInt8((blockIndex >> 24) & 0xff))
            blockSalt.append(UInt8((blockIndex >> 16) & 0xff))
            blockSalt.append(UInt8((blockIndex >> 8) & 0xff))
            blockSalt.append(UInt8(blockIndex & 0xff))

            var u = hmacSHA256(key: password, data: blockSalt)
            var t = u
            for _ in 1..<iterations {
                u = hmacSHA256(key: password, data: u)
                for index in 0..<hashByteCount {
                    t[index] ^= u[index]
                }
            }
            derived.append(t)
        }

        return derived.prefix(keyByteCount)
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(authenticationCode)
    }

    private func randomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}

private struct BackupFile: Codable {
    let version: Int
    let app: String
    let createdAt: Date
    let kdf: String
    let iterations: Int
    let salt: String
    let nonce: String
    let ciphertext: String
    let tag: String
}

private struct BackupPayload: Codable {
    let exportedAt: Date
    let records: [CredentialRecord]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
