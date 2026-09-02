import XCTest
@testable import Kanso

/// Runs projection tests (Phase 2 of `ROADMAP.md`).
///
/// These pin the two things most likely to drift into dishonesty: the attention
/// ordering, and the set of lifecycles we are willing to claim.
final class RunsProjectionTests: XCTestCase {
    private let now: Double = 1_700_000_000

    // MARK: - What we are willing to claim

    /// Guards against someone adding a `failed` case later without a server
    /// signal to back it. Verified against pinned `hermes-webui` `f1d399b4`: a
    /// session row carries no error or failure field, so failure cannot be shown
    /// truthfully and `PRODUCT.md` principle 7 forbids showing it anyway.
    func testOnlySubstantiableLifecyclesExist() {
        XCTAssertEqual(
            Set(RunLifecycle.allCases),
            [.running, .waitingForYou, .recentlyActive],
            """
            RunLifecycle gained or lost a case. A new case needs a server field that \
            substantiates it — notably there is no failure signal on /api/sessions.
            """
        )
    }

    // MARK: - Lifecycle classification

    func testWaitingForInputOutranksAnActiveStream() {
        // A stream can still be technically live while blocked on an approval.
        // What matters is that the human owns the next action.
        XCTAssertEqual(
            RunsProjection.lifecycle(
                isStreaming: true,
                isAwaitingInput: true,
                lastActivityAt: now,
                now: now
            ),
            .waitingForYou
        )
    }

    func testStreamingSessionIsRunning() {
        XCTAssertEqual(
            RunsProjection.lifecycle(
                isStreaming: true, isAwaitingInput: false, lastActivityAt: now, now: now
            ),
            .running
        )
    }

    func testFinishedRunInsideTheWindowIsRecentlyActive() {
        XCTAssertEqual(
            RunsProjection.lifecycle(
                isStreaming: false,
                isAwaitingInput: false,
                lastActivityAt: now - 60,
                now: now
            ),
            .recentlyActive
        )
    }

    func testFinishedRunOlderThanTheWindowDropsOut() {
        XCTAssertNil(
            RunsProjection.lifecycle(
                isStreaming: false,
                isAwaitingInput: false,
                lastActivityAt: now - RunsProjection.defaultRecentWindow - 1,
                now: now
            ),
            "an old finished run belongs in the session list, not in Runs"
        )
    }

    func testRunWithNoTimestampAndNoStreamIsNotShown() {
        XCTAssertNil(
            RunsProjection.lifecycle(
                isStreaming: false, isAwaitingInput: false, lastActivityAt: nil, now: now
            ),
            "without a timestamp or a stream there is nothing to substantiate"
        )
    }

    /// Phone and server clocks drift. Activity marked slightly in the future must
    /// read as current, not vanish.
    func testActivityInTheFutureIsTreatedAsCurrent() {
        XCTAssertEqual(
            RunsProjection.lifecycle(
                isStreaming: false,
                isAwaitingInput: false,
                lastActivityAt: now + 120,
                now: now
            ),
            .recentlyActive
        )
    }

    // MARK: - Rows and ordering

    func testRowsAreOrderedByAttentionThenRecency() {
        let rows = RunsProjection.rows(
            sessions: [
                session(id: "old-recent", title: "Old", lastMessageAt: now - 1800),
                session(id: "streaming", title: "Streaming", isStreaming: true, lastMessageAt: now - 5),
                session(id: "fresh-recent", title: "Fresh", lastMessageAt: now - 10),
                session(id: "waiting", title: "Waiting", lastMessageAt: now - 3000),
            ],
            awaitingInputSessionIDs: ["waiting"],
            now: now
        )

        XCTAssertEqual(
            rows.map(\.id),
            ["waiting", "streaming", "fresh-recent", "old-recent"],
            "waiting first, then running, then recent activity newest-first"
        )
        XCTAssertEqual(rows.map(\.lifecycle), [.waitingForYou, .running, .recentlyActive, .recentlyActive])
    }

    func testArchivedSessionsAreExcluded() {
        let rows = RunsProjection.rows(
            sessions: [
                session(id: "live", isStreaming: true, lastMessageAt: now),
                session(id: "archived", isStreaming: true, lastMessageAt: now, archived: true),
            ],
            now: now
        )
        XCTAssertEqual(rows.map(\.id), ["live"], "archived work is not active work")
    }

    func testSessionWithoutAnIDIsExcluded() {
        let rows = RunsProjection.rows(
            sessions: [session(id: nil, isStreaming: true, lastMessageAt: now)],
            now: now
        )
        XCTAssertTrue(
            rows.isEmpty,
            "a row with no server id cannot be opened or reconciled, so it must not be listed"
        )
    }

    func testUpdatedAtIsUsedWhenLastMessageAtIsMissing() {
        let rows = RunsProjection.rows(
            sessions: [session(id: "s", lastMessageAt: nil, updatedAt: now - 30)],
            now: now
        )
        XCTAssertEqual(rows.map(\.lifecycle), [.recentlyActive])
        XCTAssertEqual(rows.first?.lastActivityAt, now - 30)
    }

    func testBlankTitleFallsBackRatherThanRenderingEmpty() {
        let rows = RunsProjection.rows(
            sessions: [session(id: "s", title: "   ", isStreaming: true, lastMessageAt: now)],
            now: now
        )
        XCTAssertEqual(rows.first?.title, "Untitled")
    }

    func testReadOnlyAndProfileAreCarriedThrough() {
        let rows = RunsProjection.rows(
            sessions: [
                session(id: "s", isStreaming: true, lastMessageAt: now, profile: "build", readOnly: true)
            ],
            now: now
        )
        XCTAssertEqual(rows.first?.profile, "build")
        XCTAssertEqual(rows.first?.isReadOnly, true)
    }

    func testEmptyProfileIsNormalisedToNil() {
        let rows = RunsProjection.rows(
            sessions: [session(id: "s", isStreaming: true, lastMessageAt: now, profile: "")],
            now: now
        )
        XCTAssertNil(rows.first?.profile, "an empty profile must not render as a blank badge")
    }

    // MARK: - Helpers

    private func session(
        id: String?,
        title: String? = "Session",
        isStreaming: Bool? = nil,
        lastMessageAt: Double? = nil,
        updatedAt: Double? = nil,
        archived: Bool? = nil,
        profile: String? = nil,
        readOnly: Bool? = nil
    ) -> SessionSummary {
        SessionSummary(
            sessionId: id,
            title: title,
            updatedAt: updatedAt,
            lastMessageAt: lastMessageAt,
            archived: archived,
            profile: profile,
            isStreaming: isStreaming,
            readOnly: readOnly
        )
    }
}
