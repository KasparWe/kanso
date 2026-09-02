import XCTest
@testable import Kanso

@MainActor
final class NowViewModelTests: XCTestCase {
    private let serverNow: Double = 1_700_000_000

    func testComposesRunsAndSchedulesInAttentionOrder() async throws {
        let client = NowClientStub(
            sessions: .success(SessionsResponse(
                sessions: [
                    session(id: "live", isStreaming: true, lastMessageAt: serverNow - 5),
                    session(id: "recent", isStreaming: false, lastMessageAt: serverNow - 60),
                ],
                serverTime: serverNow
            )),
            crons: .success(CronJobsResponse(jobs: [try job(id: "broken", lastStatus: "error")])),
            approvalPendingSessionIDs: ["live"]
        )
        let viewModel = NowViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(
            viewModel.items.map(\.kind),
            [.waitingRun, .failedSchedule, .recentRun],
            "waiting run, then failed schedule, then recent activity"
        )
    }

    /// The header is supplementary chrome above the session list. A failing
    /// source contributes nothing rather than surfacing a second error banner.
    func testAFailedSessionsFetchStillAllowsSchedulesToShow() async throws {
        let client = NowClientStub(
            sessions: .failure(APIError.unauthorized),
            crons: .success(CronJobsResponse(jobs: [
                try job(id: "next", name: "Digest", nextRunAt: serverNow + 60, scheduleDisplay: "Daily at 07:00")
            ]))
        )
        let clock = serverNow
        let viewModel = NowViewModel(client: client, now: { clock })

        await viewModel.load()

        XCTAssertEqual(viewModel.items.map(\.kind), [.upcomingSchedule])
        XCTAssertEqual(viewModel.items.first?.title, "Digest")
    }

    func testAFailedCronFetchStillAllowsRunsToShow() async {
        let client = NowClientStub(
            sessions: .success(SessionsResponse(
                sessions: [session(id: "live", isStreaming: true, lastMessageAt: serverNow - 5)],
                serverTime: serverNow
            )),
            crons: .failure(APIError.unauthorized)
        )
        let viewModel = NowViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.items.map(\.kind), [.runningRun])
    }

    func testBothSourcesFailingProducesAnEmptyHeader() async {
        let client = NowClientStub(
            sessions: .failure(APIError.unauthorized),
            crons: .failure(APIError.unauthorized)
        )
        let viewModel = NowViewModel(client: client)

        await viewModel.load()

        XCTAssertTrue(
            viewModel.items.isEmpty,
            "an empty Now header renders nothing, which is better than an empty box"
        )
    }

    func testOnlyLiveSessionsAreProbedForWaiting() async {
        let client = NowClientStub(
            sessions: .success(SessionsResponse(
                sessions: [
                    session(id: "live", isStreaming: true, lastMessageAt: serverNow - 5),
                    session(id: "idle", isStreaming: false, lastMessageAt: serverNow - 60),
                ],
                serverTime: serverNow
            )),
            crons: .success(CronJobsResponse(jobs: []))
        )
        let viewModel = NowViewModel(client: client)

        await viewModel.load()

        let probed = await client.probedSessionIDs()
        XCTAssertEqual(probed, ["live"], "there is no global pending query, so probes stay bounded")
    }

    func testHeaderNeverExceedsThreeItems() async {
        let sessions = (0..<8).map {
            session(id: "live-\($0)", isStreaming: true, lastMessageAt: serverNow - Double($0))
        }
        let client = NowClientStub(
            sessions: .success(SessionsResponse(sessions: sessions, serverTime: serverNow)),
            crons: .success(CronJobsResponse(jobs: []))
        )
        let viewModel = NowViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.items.count, NowSummary.maximumItems)
    }

    // MARK: - Helpers

    private func session(
        id: String,
        isStreaming: Bool,
        lastMessageAt: Double?
    ) -> SessionSummary {
        SessionSummary(
            sessionId: id,
            title: "Session \(id)",
            lastMessageAt: lastMessageAt,
            isStreaming: isStreaming
        )
    }

    private func job(
        id: String,
        name: String? = nil,
        lastStatus: String? = nil,
        nextRunAt: Double? = nil,
        scheduleDisplay: String? = nil
    ) throws -> CronJob {
        var fields = ["\"job_id\": \"\(id)\""]
        if let name { fields.append("\"name\": \"\(name)\"") }
        if let lastStatus { fields.append("\"last_status\": \"\(lastStatus)\"") }
        if let nextRunAt { fields.append("\"next_run_at\": \(nextRunAt)") }
        if let scheduleDisplay { fields.append("\"schedule_display\": \"\(scheduleDisplay)\"") }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CronJob.self, from: Data("{\(fields.joined(separator: ", "))}".utf8))
    }
}

private actor NowClientStub: NowDataClient {
    private let sessionsResult: Result<SessionsResponse, Error>
    private let cronsResult: Result<CronJobsResponse, Error>
    private let approvalPendingSessionIDs: Set<String>
    private var probed: [String] = []

    init(
        sessions: Result<SessionsResponse, Error>,
        crons: Result<CronJobsResponse, Error>,
        approvalPendingSessionIDs: Set<String> = []
    ) {
        self.sessionsResult = sessions
        self.cronsResult = crons
        self.approvalPendingSessionIDs = approvalPendingSessionIDs
    }

    func probedSessionIDs() -> [String] { probed.sorted() }

    func sessions() async throws -> SessionsResponse { try sessionsResult.get() }
    func crons() async throws -> CronJobsResponse { try cronsResult.get() }

    func approvalPending(sessionID: String) async throws -> ApprovalPendingResponse {
        if !probed.contains(sessionID) { probed.append(sessionID) }
        let pending = approvalPendingSessionIDs.contains(sessionID)
        return ApprovalPendingResponse(pending: nil, pendingCount: pending ? 1 : 0)
    }

    func clarifyPending(sessionID: String) async throws -> ClarificationPendingResponse {
        if !probed.contains(sessionID) { probed.append(sessionID) }
        return ClarificationPendingResponse(pending: nil, pendingCount: 0)
    }
}
