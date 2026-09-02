import XCTest
import AppIntents
@testable import Kanso

/// Covers the New Chat App Intent plumbing (issue #337): the parameter-less deep-link URL,
/// its round-trip detection, the router bridge an intent writes to, and the intent itself.
final class AppIntentNewChatTests: XCTestCase {

    // `AppIntentRouter` is a shared singleton, so reset its pending link around every
    // test. Doing it in setUp/tearDown (rather than inline) guarantees a clean slate
    // before each test and cleanup after every exit path — including a failed assertion
    // or a thrown error mid-test — so router state can't leak between tests.
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { AppIntentRouter.shared.pendingDeepLink = nil }
    }

    override func tearDown() async throws {
        await MainActor.run { AppIntentRouter.shared.pendingDeepLink = nil }
        try await super.tearDown()
    }

    func testNewChatURLUsesNewChatHostOnTheAppScheme() throws {
        let url = try XCTUnwrap(KansoDeepLink.newChatURL)
        XCTAssertEqual(url.scheme, KansoDeepLink.scheme)
        XCTAssertEqual(url.host, KansoDeepLink.newChatHost)
    }

    func testIsNewChatURLAcceptsItsOwnURL() throws {
        let url = try XCTUnwrap(KansoDeepLink.newChatURL)
        XCTAssertTrue(KansoDeepLink.isNewChatURL(url))
    }

    func testIsNewChatURLIsCaseInsensitiveOnHost() throws {
        let url = try XCTUnwrap(URL(string: "\(KansoDeepLink.scheme)://New-Chat"))
        XCTAssertTrue(KansoDeepLink.isNewChatURL(url))
    }

    func testSessionURLIsNotANewChatURL() throws {
        let session = try XCTUnwrap(KansoDeepLink.sessionURL(sessionID: "abc123"))
        XCTAssertFalse(KansoDeepLink.isNewChatURL(session))
    }

    func testNewChatURLDoesNotParseAsASessionID() throws {
        let url = try XCTUnwrap(KansoDeepLink.newChatURL)
        XCTAssertNil(KansoDeepLink.sessionID(from: url))
    }

    func testForeignSchemeIsNotANewChatURL() throws {
        let url = try XCTUnwrap(URL(string: "https://new-chat"))
        XCTAssertFalse(KansoDeepLink.isNewChatURL(url))
    }

    @MainActor
    func testRouterRecordsDeepLink() {
        let router = AppIntentRouter.shared
        router.requestDeepLink(KansoDeepLink.newChatURL)
        XCTAssertEqual(router.pendingDeepLink, KansoDeepLink.newChatURL)
    }

    @MainActor
    func testRouterIgnoresNilDeepLink() {
        let router = AppIntentRouter.shared
        router.requestDeepLink(nil)
        XCTAssertNil(router.pendingDeepLink)
    }

    @MainActor
    func testNewChatIntentQueuesTheNewChatDeepLink() async throws {
        let router = AppIntentRouter.shared
        _ = try await NewChatIntent().perform()
        XCTAssertEqual(router.pendingDeepLink, KansoDeepLink.newChatURL)
    }

    func testIntentOpensAppWhenRun() {
        XCTAssertTrue(NewChatIntent.openAppWhenRun)
    }

    // MARK: - New Chat with Voice (issue #338)

    func testNewChatVoiceURLUsesVoiceHostOnTheAppScheme() throws {
        let url = try XCTUnwrap(KansoDeepLink.newChatVoiceURL)
        XCTAssertEqual(url.scheme, KansoDeepLink.scheme)
        XCTAssertEqual(url.host, KansoDeepLink.newChatVoiceHost)
    }

    func testIsNewChatVoiceURLAcceptsItsOwnURL() throws {
        let url = try XCTUnwrap(KansoDeepLink.newChatVoiceURL)
        XCTAssertTrue(KansoDeepLink.isNewChatVoiceURL(url))
    }

    func testIsNewChatVoiceURLIsCaseInsensitiveOnHost() throws {
        let url = try XCTUnwrap(URL(string: "\(KansoDeepLink.scheme)://New-Chat-Voice"))
        XCTAssertTrue(KansoDeepLink.isNewChatVoiceURL(url))
    }

    func testVoiceAndPlainNewChatURLsDoNotAlias() throws {
        let voiceURL = try XCTUnwrap(KansoDeepLink.newChatVoiceURL)
        let plainURL = try XCTUnwrap(KansoDeepLink.newChatURL)
        // The two intents must route distinctly: a voice URL is not a plain new-chat URL,
        // and vice versa.
        XCTAssertFalse(KansoDeepLink.isNewChatURL(voiceURL))
        XCTAssertFalse(KansoDeepLink.isNewChatVoiceURL(plainURL))
    }

    func testNewChatVoiceURLDoesNotParseAsASessionID() throws {
        let url = try XCTUnwrap(KansoDeepLink.newChatVoiceURL)
        XCTAssertNil(KansoDeepLink.sessionID(from: url))
    }

    func testSessionURLIsNotAVoiceURL() throws {
        let session = try XCTUnwrap(KansoDeepLink.sessionURL(sessionID: "abc123"))
        XCTAssertFalse(KansoDeepLink.isNewChatVoiceURL(session))
    }

    func testForeignSchemeIsNotAVoiceURL() throws {
        let url = try XCTUnwrap(URL(string: "https://new-chat-voice"))
        XCTAssertFalse(KansoDeepLink.isNewChatVoiceURL(url))
    }

    @MainActor
    func testNewChatVoiceIntentQueuesTheVoiceDeepLink() async throws {
        let router = AppIntentRouter.shared
        _ = try await NewChatVoiceIntent().perform()
        XCTAssertEqual(router.pendingDeepLink, KansoDeepLink.newChatVoiceURL)
    }

    func testVoiceIntentOpensAppWhenRun() {
        XCTAssertTrue(NewChatVoiceIntent.openAppWhenRun)
    }

    func testNewChatRequestDefaultsToVoiceOff() {
        XCTAssertFalse(NewChatRequest().autoStartsVoiceInput)
    }

    func testNewChatRequestCarriesVoiceFlag() {
        XCTAssertTrue(NewChatRequest(autoStartsVoiceInput: true).autoStartsVoiceInput)
    }
}
