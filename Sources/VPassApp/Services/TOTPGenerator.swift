import CryptoKit
import Foundation

enum TOTPError: LocalizedError {
    case invalidSecret
    case unsupportedDigits

    var errorDescription: String? {
        switch self {
        case .invalidSecret:
            return "The TOTP secret is not valid Base32."
        case .unsupportedDigits:
            return "TOTP digits must be between 1 and 9."
        }
    }
}

struct TOTPGenerator {
    static func code(
        secretBase32: String,
        date: Date = Date(),
        period: Int = 30,
        digits: Int = 6
    ) throws -> String {
        guard (1...9).contains(digits) else {
            throw TOTPError.unsupportedDigits
        }
        guard let secret = Base32.decode(secretBase32) else {
            throw TOTPError.invalidSecret
        }

        let counter = UInt64(date.timeIntervalSince1970) / UInt64(max(period, 1))
        var bigEndianCounter = counter.bigEndian
        let counterData = withUnsafeBytes(of: &bigEndianCounter) { Data($0) }
        let signature = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: secret))
        let bytes = Array(signature)
        let offset = Int(bytes[bytes.count - 1] & 0x0f)
        let truncated = UInt32(bytes[offset] & 0x7f) << 24
            | UInt32(bytes[offset + 1] & 0xff) << 16
            | UInt32(bytes[offset + 2] & 0xff) << 8
            | UInt32(bytes[offset + 3] & 0xff)
        let divisor = UInt32(pow(10.0, Double(digits)))
        let value = truncated % divisor
        return String(format: "%0*u", digits, value)
    }

    static func remainingSeconds(date: Date = Date(), period: Int = 30) -> Int {
        let safePeriod = max(period, 1)
        let elapsed = Int(date.timeIntervalSince1970) % safePeriod
        return safePeriod - elapsed
    }
}

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func decode(_ input: String) -> Data? {
        let cleaned = input
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "=" && $0 != "-" }

        guard !cleaned.isEmpty else {
            return nil
        }

        var buffer = 0
        var bitsLeft = 0
        var bytes = [UInt8]()

        for character in cleaned {
            guard let value = alphabet.firstIndex(of: character) else {
                return nil
            }
            buffer = (buffer << 5) | value
            bitsLeft += 5

            if bitsLeft >= 8 {
                bytes.append(UInt8((buffer >> (bitsLeft - 8)) & 0xff))
                bitsLeft -= 8
            }
        }

        return Data(bytes)
    }
}
