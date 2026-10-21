import Foundation

extension CredentialRecord {
    /// The letter shown on the login's list tile: the first letter or digit
    /// of its name, else of its username, else "?".
    public var monogram: String {
        for text in [title, username] {
            if let first = text.first(where: { $0.isLetter || $0.isNumber }) {
                return String(first).uppercased()
            }
        }
        return "?"
    }

    /// A stable palette slot for the login's tile. It comes from the website
    /// (so one site always gets one color) or the name when there's no
    /// website. FNV-1a, because Swift's hashValue changes on every launch.
    public func monogramColorIndex(paletteCount: Int) -> Int {
        guard paletteCount > 0 else {
            return 0
        }
        let key = (autofillDomain ?? title.trimmingCharacters(in: .whitespacesAndNewlines)).lowercased()
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(paletteCount))
    }
}

extension TOTPGenerator {
    /// Splits a code into two groups for reading: "123 456", "1234 5678".
    public static func grouped(_ code: String) -> String {
        guard code.count >= 6 else {
            return code
        }
        let split = code.index(code.startIndex, offsetBy: (code.count + 1) / 2)
        return "\(code[..<split]) \(code[split...])"
    }
}
