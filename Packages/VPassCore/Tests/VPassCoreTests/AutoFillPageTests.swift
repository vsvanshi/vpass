import XCTest
import VPassCore

final class AutoFillPageTests: XCTestCase {
    // Shape of a real Keycloak sign-in page (state/nonce values shortened).
    private let keycloakPage = "https://platform.infinx.com/auth/realms/mnr_ai_d_ortho/protocol/openid-connect/auth?client_id=api-app&redirect_uri=https%3A%2F%2Fauthreviewai.infinx.com%2Fmedui%2Fmnr_ai_d_ortho%2Fhome&state=s&response_mode=fragment&response_type=code&scope=openid&nonce=n"

    private let medicalNecessity = CredentialRecord(title: "Medical Necessity", username: "varun@infinx.com", url: "https://authreviewai.infinx.com/medui/mnr_ai_d_ortho/home")
    private let otherRealmSameHost = CredentialRecord(title: "Other AI App", username: "varun@infinx.com", url: "https://authreviewai.infinx.com/medui/other_realm/home")
    private let platformApp = CredentialRecord(title: "Platform", username: "varun@infinx.com", url: "platform.infinx.com")
    private let invoiceIQ = CredentialRecord(title: "Invoice IQ Dev", username: "varun@infinx.com", url: "codingdev.infinx.com")

    func testParsesRedirectTargetAndRealm() {
        let page = AutoFillPage(serviceIdentifier: keycloakPage)

        XCTAssertEqual(page.host, "platform.infinx.com")
        XCTAssertEqual(page.realm, "mnr_ai_d_ortho")
        XCTAssertEqual(page.targets.map(\.host), ["authreviewai.infinx.com"])
        XCTAssertEqual(page.displayHost, "authreviewai.infinx.com")
    }

    func testRedirectTargetBeatsSharedLoginHost() {
        let page = AutoFillPage(serviceIdentifier: keycloakPage)

        XCTAssertEqual(medicalNecessity.autofillScore(for: page), 3)
        XCTAssertEqual(otherRealmSameHost.autofillScore(for: page), 2)
        XCTAssertEqual(platformApp.autofillScore(for: page), 2)
        XCTAssertEqual(invoiceIQ.autofillScore(for: page), 0)
    }

    func testRealmAloneIdentifiesTheAppWhenQueryIsMissing() {
        let page = AutoFillPage(serviceIdentifier: "https://platform.infinx.com/auth/realms/mnr_ai_d_ortho/protocol/openid-connect/auth")

        XCTAssertEqual(medicalNecessity.autofillScore(for: page), 3)
        XCTAssertEqual(otherRealmSameHost.autofillScore(for: page), 0)
    }

    func testCASServiceParameterIsATarget() {
        let page = AutoFillPage(serviceIdentifier: "https://sso.example.com/cas/login?service=https%3A%2F%2Fapp.example.com%2F")
        let app = CredentialRecord(title: "App", username: "u", url: "app.example.com")

        XCTAssertEqual(app.autofillScore(for: page), 3)
    }

    func testOrdinaryPagesStillMatchByHost() {
        let page = AutoFillPage(serviceIdentifier: "https://github.com/login")

        XCTAssertNil(page.realm)
        XCTAssertTrue(page.targets.isEmpty)
        XCTAssertEqual(CredentialRecord(title: "GitHub", username: "v", url: "github.com").autofillScore(for: page), 2)
        XCTAssertEqual(CredentialRecord(title: "Gist", username: "v", url: "gist.github.com").autofillScore(for: page), 1)
        XCTAssertEqual(CredentialRecord(title: "GitLab", username: "v", url: "gitlab.com").autofillScore(for: page), 0)
    }
}
