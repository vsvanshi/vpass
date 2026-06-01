import Foundation
import XCTest
@testable import VPassApp

final class TOTPGeneratorTests: XCTestCase {
    func testRFC6238Vector() throws {
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        let date = Date(timeIntervalSince1970: 59)
        let code = try TOTPGenerator.code(secretBase32: secret, date: date, period: 30, digits: 8)
        XCTAssertEqual(code, "94287082")
    }

    func testParserReadsOTPAuthQRCodePayload() throws {
        let payload = "otpauth://totp/Hetzner:varun@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Hetzner&period=30&digits=6"
        let config = try OTPAuthParser.parse(payload)
        XCTAssertEqual(config.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(config.issuer, "Hetzner")
        XCTAssertEqual(config.account, "varun@example.com")
        XCTAssertEqual(config.period, 30)
        XCTAssertEqual(config.digits, 6)
    }
}
