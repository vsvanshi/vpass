import Foundation

struct OTPAuthConfig: Equatable {
    var secret: String
    var issuer: String
    var account: String
    var period: Int
    var digits: Int
}

enum OTPAuthParserError: LocalizedError {
    case unsupportedURL
    case missingSecret
    case invalidSecret

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "That QR code is not a supported otpauth://totp URL."
        case .missingSecret:
            return "The QR code does not contain a TOTP secret."
        case .invalidSecret:
            return "The QR code contains an invalid Base32 TOTP secret."
        }
    }
}

struct OTPAuthParser {
    static func parse(_ payload: String) throws -> OTPAuthConfig {
        guard let components = URLComponents(string: payload),
              components.scheme == "otpauth",
              components.host == "totp" else {
            throw OTPAuthParserError.unsupportedURL
        }

        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name.lowercased(), $0) }
            }
        )

        guard let secret = query["secret"], !secret.isEmpty else {
            throw OTPAuthParserError.missingSecret
        }
        guard Base32.decode(secret) != nil else {
            throw OTPAuthParserError.invalidSecret
        }

        let decodedLabel = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .removingPercentEncoding ?? ""
        let labelParts = decodedLabel.split(separator: ":", maxSplits: 1).map(String.init)
        let issuer = query["issuer"] ?? labelParts.first ?? ""
        let account = labelParts.count == 2 ? labelParts[1] : decodedLabel

        return OTPAuthConfig(
            secret: secret,
            issuer: issuer,
            account: account,
            period: Int(query["period"] ?? "") ?? 30,
            digits: Int(query["digits"] ?? "") ?? 6
        )
    }
}
