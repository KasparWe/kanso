import XCTest
@testable import HermesMobile

final class OnboardingFlowTests: XCTestCase {
    /// Issue #285: a probed auth status belongs to the URL and headers it was probed
    /// against. Editing either must invalidate it, or `isPasswordRequired` can hide
    /// the password field using another server's trusted-header state and `connect()`
    /// skips the re-probe, leaving no way to supply the password the new server wants.
    @MainActor
    func testEditingServerURLInvalidatesTheProbedAuthStatus() throws {
        let viewModel = OnboardingViewModel()
        viewModel.serverURLString = "https://trusted.example.test"
        viewModel.applyProbedAuthStatus(try Self.authStatus(
            #"{"auth_enabled": true, "logged_in": true, "trusted_auth_enabled": true}"#
        ))

        XCTAssertFalse(
            viewModel.isPasswordRequired,
            "a trusted-header server that already signed us in needs no password"
        )

        viewModel.serverURLString = "https://password.example.test"

        XCTAssertTrue(
            viewModel.isPasswordRequired,
            "editing the server URL must invalidate the probe and show the password field again"
        )
        XCTAssertNil(
            viewModel.currentAuthStatus,
            "a status probed against a different server must not be treated as current"
        )
    }

    @MainActor
    func testEditingCustomHeadersInvalidatesTheProbedAuthStatus() throws {
        let viewModel = OnboardingViewModel()
        viewModel.serverURLString = "https://trusted.example.test"
        viewModel.applyProbedAuthStatus(try Self.authStatus(
            #"{"auth_enabled": true, "logged_in": true, "trusted_auth_enabled": true}"#
        ))
        XCTAssertFalse(viewModel.isPasswordRequired)

        // The headers are what make a trusted-header proxy authenticate us, so
        // changing them can change the answer entirely.
        viewModel.customHeaders = [CustomHeader(name: "Cf-Access-Jwt-Assertion", value: "token")]

        XCTAssertTrue(
            viewModel.isPasswordRequired,
            "editing custom headers must invalidate the probe"
        )
        XCTAssertNil(viewModel.currentAuthStatus)
    }

    /// Re-probing against the edited server must make the status current again.
    @MainActor
    func testReprobingAfterAnEditRestoresTheStatus() throws {
        let viewModel = OnboardingViewModel()
        viewModel.serverURLString = "https://first.example.test"
        viewModel.applyProbedAuthStatus(try Self.authStatus(#"{"auth_enabled": false}"#))
        XCTAssertFalse(viewModel.isPasswordRequired)

        viewModel.serverURLString = "https://second.example.test"
        XCTAssertTrue(viewModel.isPasswordRequired)

        viewModel.applyProbedAuthStatus(try Self.authStatus(#"{"auth_enabled": false}"#))
        XCTAssertFalse(
            viewModel.isPasswordRequired,
            "a fresh probe against the edited server is current again"
        )
        XCTAssertNotNil(viewModel.currentAuthStatus)
    }

    private static func authStatus(_ json: String) throws -> AuthStatusResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AuthStatusResponse.self, from: Data(json.utf8))
    }

    func testPrimaryButtonTitlesFollowPagerFlow() {
        XCTAssertEqual(OnboardingFlowPolicy.primaryButtonTitle(for: 0), "Get Started")
        XCTAssertEqual(OnboardingFlowPolicy.primaryButtonTitle(for: 1), "Set Up")
        XCTAssertEqual(OnboardingFlowPolicy.primaryButtonTitle(for: 2), "Continue")
        XCTAssertEqual(OnboardingFlowPolicy.primaryButtonTitle(for: 3), "Continue")
        XCTAssertEqual(OnboardingFlowPolicy.primaryButtonTitle(for: 4), "Connect")
    }

    func testCopyReminderOnlyAppliesToAgentPromptPageWithoutCopy() {
        XCTAssertTrue(
            OnboardingFlowPolicy.shouldShowCopyReminder(
                page: OnboardingFlowPolicy.agentPromptPageIndex,
                hasCopiedAgentPrompt: false
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldShowCopyReminder(
                page: OnboardingFlowPolicy.agentPromptPageIndex,
                hasCopiedAgentPrompt: true
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldShowCopyReminder(
                page: OnboardingFlowPolicy.agentPromptPageIndex,
                hasCopiedAgentPrompt: false,
                hasBypassedCopyReminder: true
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldShowCopyReminder(
                page: OnboardingFlowPolicy.connectPageIndex,
                hasCopiedAgentPrompt: false
            )
        )
    }

    func testForwardSwipeFromAgentPromptRequiresCopyOrBypass() {
        XCTAssertTrue(
            OnboardingFlowPolicy.shouldInterceptForwardNavigationFromAgentPrompt(
                from: OnboardingFlowPolicy.agentPromptPageIndex,
                to: 3,
                hasCopiedAgentPrompt: false
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldInterceptForwardNavigationFromAgentPrompt(
                from: OnboardingFlowPolicy.agentPromptPageIndex,
                to: 3,
                hasCopiedAgentPrompt: true
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldInterceptForwardNavigationFromAgentPrompt(
                from: OnboardingFlowPolicy.agentPromptPageIndex,
                to: 3,
                hasCopiedAgentPrompt: false,
                hasBypassedCopyReminder: true
            )
        )
        XCTAssertFalse(
            OnboardingFlowPolicy.shouldInterceptForwardNavigationFromAgentPrompt(
                from: OnboardingFlowPolicy.agentPromptPageIndex,
                to: 1,
                hasCopiedAgentPrompt: false
            )
        )
    }

    func testConnectFocusClearsWhenLeavingConnectPage() {
        XCTAssertTrue(OnboardingFlowPolicy.shouldClearConnectFocusWhenLeavingPage(3))
        XCTAssertFalse(OnboardingFlowPolicy.shouldClearConnectFocusWhenLeavingPage(OnboardingFlowPolicy.connectPageIndex))
    }

    func testServerShortcutShowsBeforeConnectPageOnly() {
        XCTAssertTrue(OnboardingFlowPolicy.showsServerShortcut(for: 0))
        XCTAssertTrue(OnboardingFlowPolicy.showsServerShortcut(for: 3))
        XCTAssertFalse(OnboardingFlowPolicy.showsServerShortcut(for: OnboardingFlowPolicy.connectPageIndex))
    }

    func testAgentSetupPromptDefaultsToSafeStateAwareTailscaleServe() {
        let prompt = OnboardingFlowPolicy.agentSetupPrompt

        let requiredInstructions = [
            "Python standard library + vanilla JavaScript",
            "Inventory before changing anything",
            "command -v tailscale",
            "tailscale version",
            "tailscale status",
            "Only if `command -v tailscale` reports that Tailscale is absent",
            "correct method for this OS",
            "rerun `tailscale version`, `tailscale status`, and the authentication check",
            "tailscale serve status",
            "tailscale funnel status",
            "lsof -nP -iTCP:8787 -sTCP:LISTEN",
            "Do not kill an unknown process",
            "Do not run tailscale serve reset",
            "127.0.0.1:8787",
            "only if HTTPS port 443 at the root path is free",
            "tailscale serve --bg 8787",
            "Never enable Funnel",
            "HTTPS consent",
            "certificate-transparency disclosure",
            "umask 077",
            "chmod 600",
            "Preserve every existing line in `.env`",
            "only add or update the `HERMES_WEBUI_PASSWORD` entry",
            "never truncate or replace the file",
            "Whether `.env` already existed or is new",
            "Do not print the full .env",
            "python3 bootstrap.py",
            "./ctl.sh",
            "Do not configure auto-start yourself",
            "Propose the exact OS-appropriate commands and steps",
            "wait for me to run them",
            "Do not touch `~/Library/LaunchAgents/` or restart Mac services",
            "curl --fail http://127.0.0.1:8787/health",
            "actual ts.net HTTPS URL",
            "exact HTTPS URL, password, launcher, and both health-check results",
            "manual fallback",
            "Do not automate it"
        ]

        for instruction in requiredInstructions {
            XCTAssertTrue(prompt.contains(instruction), "Missing safe setup instruction: \(instruction)")
        }

        XCTAssertFalse(prompt.contains("Node.js"))
        XCTAssertFalse(prompt.contains("curl http://$(tailscale ip -4):8787/health"))
        XCTAssertFalse(prompt.contains("fall back: bind the server to 0.0.0.0"))
        XCTAssertFalse(prompt.contains("Otherwise configure auto-start appropriate for this OS"))
    }

    func testTailscaleAppStoreURLUsesITMSDeepLink() {
        XCTAssertEqual(
            OnboardingFlowPolicy.tailscaleAppStoreURL.absoluteString,
            "itms-apps://apps.apple.com/us/app/tailscale/id1470499037"
        )
        XCTAssertEqual(
            OnboardingFlowPolicy.tailscaleAppStoreFallbackURL.absoluteString,
            "https://apps.apple.com/us/app/tailscale/id1470499037"
        )
    }

    func testConnectPageIndexIsFinalPagerPage() {
        XCTAssertEqual(OnboardingFlowPolicy.connectPageIndex, OnboardingFlowPolicy.pageCount - 1)
    }
}
