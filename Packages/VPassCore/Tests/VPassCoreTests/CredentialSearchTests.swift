import XCTest
import VPassCore

final class CredentialSearchTests: XCTestCase {
    func testSearchMatchesWordsInAnyOrder() {
        let record = CredentialRecord(title: "Stage platform core")

        XCTAssertTrue(record.matchesSearch("platform stage"))
        XCTAssertTrue(record.matchesSearch("plat stag"))
        XCTAssertFalse(record.matchesSearch("platform production"))
    }
}
