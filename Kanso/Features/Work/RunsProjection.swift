import Foundation

/// Lifecycle a run can be shown in, restricted to what the server can actually
/// substantiate (Phase 2 of `ROADMAP.md`).
///
/// `PRODUCT.md` principle 7 forbids asserting state we cannot back with server
/// data, and there is deliberately **no `failed` case**: verified against the
/// pinned `hermes-webui` (`f1d399b4`), a session row from `/api/sessions` carries
/// no error or failure field. `Session.compact()` in `api/models.py` emits
/// `is_streaming`, `active_stream_id`, `pending_user_message` and timestamps, but
/// nothing that distinguishes "finished" from "crashed". Adding a `failed` case
/// here would mean inventing it.
enum RunLifecycle: String, CaseIterable, Equatable, Sendable {
    /// The server confirms a live stream for this session. `is_streaming` is a
    /// real runtime check — `all_sessions()` passes `include_runtime: true`, and
    /// `_is_streaming_session` tests `active_stream_id in active_stream_ids`,
    /// so it cannot be a stale persisted flag.
    case running

    /// An approval or clarification is pending, so the run cannot progress until
    /// the human answers. Sourced separately from `/api/approval/pending` and
    /// `/api/clarify/pending` — it is not present on a session row.
    case waitingForYou

    /// Not streaming, but touched recently enough to still be worth showing.
    /// Deliberately *not* called "completed": absent a failure signal, we know
    /// the stream ended, not that it succeeded.
    case recentlyActive

    /// Attention order, most urgent first. Mirrors the `PRODUCT.md` Home
    /// priority list, minus the states the server cannot substantiate.
    var attentionRank: Int {
        switch self {
        case .waitingForYou: 0
        case .running: 1
        case .recentlyActive: 2
        }
    }
}

/// One row in the Work → Runs list.
struct RunRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let lifecycle: RunLifecycle
    /// `last_message_at`, falling back to `updated_at`. Nil when the server sent
    /// neither, which sorts last rather than pretending to be "now".
    let lastActivityAt: Double?
    let profile: String?
    let isReadOnly: Bool
}

/// Pure projection from a sessions list to Runs rows.
///
/// Kept free of networking and view state so the attention ordering and the
/// recency boundary are testable without a server or a simulator.
enum RunsProjection {
    /// Default window for `recentlyActive`. An hour is long enough to still show
    /// a run you stepped away from, short enough that Runs does not become a
    /// second session list.
    static let defaultRecentWindow: TimeInterval = 3600

    /// - Parameters:
    ///   - sessions: rows as returned by `/api/sessions`.
    ///   - awaitingInputSessionIDs: sessions with a pending approval or
    ///     clarification. Passed in rather than fetched so this stays pure and so
    ///     the caller decides how to merge the two `pending` endpoints.
    ///   - now: current time as a Unix timestamp, injected for deterministic tests.
    ///   - recentWindow: how long after last activity a finished run stays listed.
    static func rows(
        sessions: [SessionSummary],
        awaitingInputSessionIDs: Set<String> = [],
        now: Double,
        recentWindow: TimeInterval = defaultRecentWindow
    ) -> [RunRow] {
        let rows: [RunRow] = sessions.compactMap { session in
            // A row with no server-assigned id cannot be addressed, deep-linked,
            // or reconciled, so it has no place in an operational list.
            guard let sessionID = session.sessionId, !sessionID.isEmpty else { return nil }
            // Archived sessions are explicitly out of active work.
            guard session.archived != true else { return nil }

            let lastActivity = session.lastMessageAt ?? session.updatedAt

            guard let lifecycle = lifecycle(
                isStreaming: session.isStreaming == true,
                isAwaitingInput: awaitingInputSessionIDs.contains(sessionID),
                lastActivityAt: lastActivity,
                now: now,
                recentWindow: recentWindow
            ) else { return nil }

            return RunRow(
                id: sessionID,
                title: displayTitle(for: session),
                lifecycle: lifecycle,
                lastActivityAt: lastActivity,
                profile: session.profile?.isEmpty == true ? nil : session.profile,
                isReadOnly: session.readOnly == true
            )
        }

        return rows.sorted { left, right in
            if left.lifecycle.attentionRank != right.lifecycle.attentionRank {
                return left.lifecycle.attentionRank < right.lifecycle.attentionRank
            }
            // Most recent first; rows with no timestamp sink to the bottom of
            // their group instead of being treated as brand new.
            let leftActivity = left.lastActivityAt ?? -.greatestFiniteMagnitude
            let rightActivity = right.lastActivityAt ?? -.greatestFiniteMagnitude
            if leftActivity != rightActivity { return leftActivity > rightActivity }
            return left.id < right.id
        }
    }

    /// `nil` means "not part of active work" — a finished run older than the
    /// window belongs in the session list, not in Runs.
    ///
    /// Waiting outranks running: a stream can still be technically live while
    /// blocked on an approval, and the human's next action is what matters.
    static func lifecycle(
        isStreaming: Bool,
        isAwaitingInput: Bool,
        lastActivityAt: Double?,
        now: Double,
        recentWindow: TimeInterval = defaultRecentWindow
    ) -> RunLifecycle? {
        if isAwaitingInput { return .waitingForYou }
        if isStreaming { return .running }
        guard let lastActivityAt else { return nil }
        // Clock skew between phone and server can put activity slightly in the
        // future; treat that as current rather than dropping the row.
        let age = now - lastActivityAt
        guard age <= recentWindow else { return nil }
        return .recentlyActive
    }

    private static func displayTitle(for session: SessionSummary) -> String {
        let trimmed = session.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(localized: "Untitled") : trimmed
    }
}
