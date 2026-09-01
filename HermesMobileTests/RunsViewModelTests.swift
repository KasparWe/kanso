import XCTest
@testable import HermesMobile

@MainActor
final class RunsViewModelTests: XCTestCase {
    private let serverNow: Double = 1_700_000_000

    func testLiveRunWithAPendingApprovalIsWaitingForYou() async {
        let client = RunsClientStub(
            sessions: .success(response(sessions: [
                session(id: "live", isStreaming: true, lastMessageAt: serverNow - 5)
            ])),
            approvalPendingSessionIDs: ["live"]
        )
        let viewModel = RunsViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.lifecycle), [.waitingForYou])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.didLimitWaitingProbes)
    }

    func testClarificationAlsoCountsAsWaiting() async {
        let client = RunsClientStub(
            sessions: .success(response(sessions: [
                session(id: "live", isStreaming: true, lastMessageAt: serverNow - 5)
            ])),
            clarifyPendingSessionIDs: ["live"]
        )
        let viewModel = RunsViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.lifecycle), [.waitingForYou])
    }

    /// The server has no global pending query, so probing every session would be
    /// one request each. Only live runs can be blocked on input, so only they are
    /// probed.
    func testOnlyStreamingSessionsAreProbed() async {
        let client = RunsClientStub(
            sessions: .success(response(sessions: [
                session(id: "live", isStreaming: true, lastMessageAt: serverNow - 5),
                session(id: "idle", isStreaming: false, lastMessageAt: serverNow - 60),
                session(id: "archived", isStreaming: true, lastMessageAt: serverNow, archived: true),
            ]))
        )
        let viewModel = RunsViewModel(client: client)

        await viewModel.load()

        let probed = await client.probedSessionIDs()
        XCTAssertEqual(
            probed,
            ["live"],
            "idle sessions cannot be awaiting input, and archived work is out of scope"
        )
    }

    /// A failed probe must degrade to "running", never to a claim of waiting.
    func testFailedProbeLeavesTheRunAsRunning() async {
        let client = RunsClientStub(
            sessions: .success(response(sessions: [
                session(id: "live", isStreaming: true, lastMessageAt: serverNow - 5)
            ])),
            pendingError: APIError.unauthorized
        )
        let viewModel = RunsViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.lifecycle), [.running])
        XCTAssertNil(viewModel.errorMessage, "a probe failure must not fail the whole refresh")
    }

    func testProbeCapIsReportedRatherThanHidden() async {
        let live = (0..<(RunsViewModel.maximumWaitingProbes + 3)).map {
            session(id: "live-\($0)", isStreaming: true, lastMessageAt: serverNow - Double($0))
        }
        let client = RunsClientStub(sessions: .success(response(sessions: live)))
        let viewModel = RunsViewModel(client: client)

        await viewModel.load()

        let probed = await client.probedSessionIDs()
        XCTAssertEqual(probed.count, RunsViewModel.maximumWaitingProbes)
        XCTAssertTrue(
            viewModel.didLimitWaitingProbes,
            "a cap the UI cannot see reads as 'checked everything and found nothing'"
        )
        XCTAssertEqual(
            viewModel.rows.count, live.count,
            "capping probes must not drop rows — they simply stay classified as running"
        )
    }

    /// The server's clock drives the recency window, so phone drift cannot age a
    /// run out of the list.
    func testServerTimeDrivesTheRecencyWindow() async {
        let client = RunsClientStub(
            sessions: .success(response(
                sessions: [session(id: "recent", isStreaming: false, lastMessageAt: serverNow - 60)],
                serverTime: serverNow
            ))
        )
        // A device clock hours ahead would drop the row if it were used.
        let skewedClock = serverNow + 86_400
        let viewModel = RunsViewModel(client: client, now: { skewedClock })

        await viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.lifecycle), [.recentlyActive])
    }

    func testDeviceClockIsUsedOnlyWhenTheServerOmitsItsTime() async {
        let client = RunsClientStub(
            sessions: .success(response(
                sessions: [session(id: "recent", isStreaming: false, lastMessageAt: serverNow - 60)],
                serverTime: nil
            ))
        )
        let deviceClock = serverNow
        let viewModel = RunsViewModel(client: client, now: { deviceClock })

        await viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.lifecycle), [.recentlyActive])
    }

    func testAFailedSessionsFetchSurfacesAnErrorAndKeepsExistingRows() async {
        let client = RunsClientStub(
            sessions: .success(response(sessions: [
                session(id: "live", isStreaming: true, lastMessageAt: serverNow - 5)
            ]))
        )
        let viewModel = RunsViewModel(client: client)
        await viewModel.load()
        XCTAssertEqual(viewModel.rows.count, 1)

        await client.setSessions(.failure(APIError.unauthorized))
        await viewModel.load()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(
            viewModel.rows.count, 1,
            "a failed refresh must not blank a list the user is reading"
        )
    }

    // MARK: - Helpers

    private func response(sessions: [SessionSummary], serverTime: Double? = nil) -> SessionsResponse {
        SessionsResponse(sessions: sessions, serverTime: serverTime)
    }

    private func session(
        id: String,
        isStreaming: Bool,
        lastMessageAt: Double?,
        archived: Bool? = nil
    ) -> SessionSummary {
        SessionSummary(
            sessionId: id,
            title: "Session \(id)",
            lastMessageAt: lastMessageAt,
            archived: archived,
            isStreaming: isStreaming
        )
    }
}

private actor RunsClientStub: RunsDataClient {
    private var sessionsResult: Result<SessionsResponse, Error>
    private let approvalPendingSessionIDs: Set<String>
    private let clarifyPendingSessionIDs: Set<String>
    private let pendingError: Error?
    private var probed: [String] = []

    init(
        sessions: Result<SessionsResponse, Error>,
        approvalPendingSessionIDs: Set<String> = [],
        clarifyPendingSessionIDs: Set<String> = [],
        pendingError: Error? = nil
    ) {
        self.sessionsResult = sessions
        self.approvalPendingSessionIDs = approvalPendingSessionIDs
        self.clarifyPendingSessionIDs = clarifyPendingSessionIDs
        self.pendingError = pendingError
    }

    func setSessions(_ result: Result<SessionsResponse, Error>) { sessionsResult = result }
    func probedSessionIDs() -> [String] { probed.sorted() }

    func sessions() async throws -> SessionsResponse { try sessionsResult.get() }

    func approvalPending(sessionID: String) async throws -> ApprovalPendingResponse {
        if !probed.contains(sessionID) { probed.append(sessionID) }
        if let pendingError { throw pendingError }
        let isPending = approvalPendingSessionIDs.contains(sessionID)
        return ApprovalPendingResponse(pending: nil, pendingCount: isPending ? 1 : 0)
    }

    func clarifyPending(sessionID: String) async throws -> ClarificationPendingResponse {
        if !probed.contains(sessionID) { probed.append(sessionID) }
        if let pendingError { throw pendingError }
        let isPending = clarifyPendingSessionIDs.contains(sessionID)
        return ClarificationPendingResponse(pending: nil, pendingCount: isPending ? 1 : 0)
    }
}
