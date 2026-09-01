import XCTest
@testable import HermesMobile

final class NowSummaryTests: XCTestCase {
    private let now: Double = 1_700_000_000

    // MARK: - What Now is willing to claim

    /// Mirrors `RunsProjectionTests.testOnlySubstantiableLifecyclesExist`. Note
    /// what is absent: no `failedRun` (a session row has no error field) and no
    /// `blocked` (Kanban is not wired to a real board yet).
    func testOnlySubstantiableKindsExist() {
        XCTAssertEqual(
            Set(NowItemKind.allCases),
            [.waitingRun, .failedSchedule, .runningRun, .recentRun, .upcomingSchedule],
            """
            NowItemKind changed. A new kind needs a server field behind it — there is \
            still no failure signal on a session row and no real Kanban board.
            """
        )
    }

    func testHeaderIsCappedAtThreeItems() {
        let runs = (0..<6).map { run(id: "r\($0)", lifecycle: .running) }

        let items = NowSummary.items(runs: runs, now: now)

        XCTAssertEqual(
            items.count, NowSummary.maximumItems,
            "PRODUCT.md caps the Now header at three items"
        )
    }

    func testItemsFollowTheProductAttentionOrder() throws {
        let items = NowSummary.items(
            runs: [
                run(id: "recent", lifecycle: .recentlyActive),
                run(id: "running", lifecycle: .running),
                run(id: "waiting", lifecycle: .waitingForYou),
            ],
            schedules: [
                try job(id: "broken", name: "Nightly", lastStatus: "error"),
            ],
            now: now
        )

        XCTAssertEqual(
            items.map(\.kind),
            [.waitingRun, .failedSchedule, .runningRun],
            "waiting first, then a failed schedule, then running — recent is cut by the cap"
        )
    }

    func testWaitingRunWinsEvenWhenAScheduleHasFailed() throws {
        let items = NowSummary.items(
            runs: [run(id: "waiting", lifecycle: .waitingForYou)],
            schedules: [try job(id: "broken", lastStatus: "error")],
            now: now
        )
        XCTAssertEqual(items.first?.kind, .waitingRun, "a human being blocked outranks a failure")
    }

    // MARK: - Schedule attention

    func testExplicitErrorSignalsNeedAttention() throws {
        XCTAssertTrue(NowSummary.needsAttention(try job(id: "a", lastStatus: "error")))
        XCTAssertTrue(NowSummary.needsAttention(try job(id: "b", state: "error")))
    }

    /// Under-reporting is the safe direction: a false warning trains the user to
    /// ignore the header.
    func testHealthyOrMerelyDisabledSchedulesDoNotNeedAttention() throws {
        XCTAssertFalse(NowSummary.needsAttention(try job(id: "ok", lastStatus: "ok")))
        XCTAssertFalse(NowSummary.needsAttention(try job(id: "success", lastStatus: "success")))
        XCTAssertFalse(NowSummary.needsAttention(try job(id: "paused", state: "paused")))
        XCTAssertFalse(
            NowSummary.needsAttention(try job(id: "off", enabled: false, state: "completed", lastStatus: "ok")),
            "a completed one-shot is not a failure"
        )
    }

    func testServerErrorMessageIsPreferredOverAGenericLabel() throws {
        let items = NowSummary.items(
            runs: [],
            schedules: [try job(id: "broken", name: "Nightly", lastStatus: "error", lastError: "provider timeout")],
            now: now
        )
        XCTAssertEqual(items.first?.detail, "provider timeout")
    }

    func testGenericLabelIsUsedWhenTheServerGivesNoMessage() throws {
        let items = NowSummary.items(
            runs: [],
            schedules: [try job(id: "broken", lastStatus: "error")],
            now: now
        )
        XCTAssertEqual(items.first?.detail, "Last run failed")
    }

    // MARK: - Upcoming schedule

    func testSoonestFutureRunIsChosen() throws {
        let soonest = try job(id: "soon", name: "Soon", nextRunAt: now + 60)
        let later = try job(id: "later", name: "Later", nextRunAt: now + 600)

        XCTAssertEqual(NowSummary.nextUpcoming(schedules: [later, soonest], now: now)?.id, "soon")
    }

    func testPastRunsAndDisabledSchedulesAreNotUpcoming() throws {
        let past = try job(id: "past", nextRunAt: now - 60)
        let disabled = try job(id: "disabled", enabled: false, nextRunAt: now + 60)

        XCTAssertNil(NowSummary.nextUpcoming(schedules: [past, disabled], now: now))
    }

    /// A broken schedule already appears as `failedSchedule`; listing it again as
    /// "upcoming" would double-count it and imply it is healthy.
    func testAFailedScheduleIsNotAlsoShownAsUpcoming() throws {
        let broken = try job(id: "broken", lastStatus: "error", nextRunAt: now + 60)

        XCTAssertNil(NowSummary.nextUpcoming(schedules: [broken], now: now))

        let items = NowSummary.items(runs: [], schedules: [broken], now: now)
        XCTAssertEqual(items.map(\.kind), [.failedSchedule])
    }

    func testUpcomingScheduleAppearsWhenNothingElseCompetes() throws {
        let items = NowSummary.items(
            runs: [],
            schedules: [try job(id: "next", name: "Digest", nextRunAt: now + 60, scheduleDisplay: "Daily at 07:00")],
            now: now
        )
        XCTAssertEqual(items.map(\.kind), [.upcomingSchedule])
        XCTAssertEqual(items.first?.title, "Digest")
        XCTAssertEqual(items.first?.detail, "Daily at 07:00")
    }

    func testEmptyInputsProduceNoItems() {
        XCTAssertTrue(NowSummary.items(runs: [], schedules: [], now: now).isEmpty)
    }

    /// A session and a cron job could share an id; ids must stay unique so
    /// SwiftUI does not collapse two rows into one.
    func testItemIDsAreUniquePerKind() throws {
        let items = NowSummary.items(
            runs: [run(id: "shared", lifecycle: .running)],
            schedules: [try job(id: "shared", lastStatus: "error")],
            now: now
        )
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
    }

    // MARK: - Helpers

    private func run(id: String, lifecycle: RunLifecycle) -> RunRow {
        RunRow(
            id: id,
            title: "Run \(id)",
            lifecycle: lifecycle,
            lastActivityAt: now,
            profile: nil,
            isReadOnly: false
        )
    }

    /// `CronJob` is decode-only, so fixtures go through JSON — which also keeps
    /// them honest about the real wire shape.
    private func job(
        id: String,
        name: String? = nil,
        enabled: Bool? = nil,
        state: String? = nil,
        lastStatus: String? = nil,
        lastError: String? = nil,
        nextRunAt: Double? = nil,
        scheduleDisplay: String? = nil
    ) throws -> CronJob {
        var fields: [String] = ["\"job_id\": \"\(id)\""]
        if let name { fields.append("\"name\": \"\(name)\"") }
        if let enabled { fields.append("\"enabled\": \(enabled)") }
        if let state { fields.append("\"state\": \"\(state)\"") }
        if let lastStatus { fields.append("\"last_status\": \"\(lastStatus)\"") }
        if let lastError { fields.append("\"last_error\": \"\(lastError)\"") }
        if let nextRunAt { fields.append("\"next_run_at\": \(nextRunAt)") }
        if let scheduleDisplay { fields.append("\"schedule_display\": \"\(scheduleDisplay)\"") }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CronJob.self, from: Data("{\(fields.joined(separator: ", "))}".utf8))
    }
}
