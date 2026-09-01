import Foundation
import Observation

/// Backing model for Work → Runs (Phase 2 of `ROADMAP.md`).
///
/// Composes `/api/sessions` with the per-session pending probes, then hands both
/// to `RunsProjection`. All state-classification rules live in the projection so
/// they stay pure and testable; this type only fetches and reconciles.
@MainActor
@Observable
final class RunsViewModel {
    private(set) var rows: [RunRow] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// True when the pending-probe cap kept us from checking every live run, so
    /// the UI can say "some runs may be waiting" instead of implying none are.
    /// Never silently swallowed — a cap that is invisible reads as "checked
    /// everything and found nothing".
    private(set) var didLimitWaitingProbes = false

    /// Upper bound on per-session pending probes per load.
    ///
    /// The server exposes no global pending query, so each live run costs one
    /// request. In practice only a handful of sessions stream at once, but a
    /// broken or hostile server could report hundreds; this keeps one refresh
    /// from turning into hundreds of requests. Exceeding it only loses
    /// *waiting* detection — those runs still show as `running`, which is
    /// already substantiated — so the cap can never invent state.
    static let maximumWaitingProbes = 12

    private let client: any RunsDataClient
    private let recentWindow: TimeInterval
    private let now: @Sendable () -> Double

    init(
        client: any RunsDataClient,
        recentWindow: TimeInterval = RunsProjection.defaultRecentWindow,
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }
    ) {
        self.client = client
        self.recentWindow = recentWindow
        self.now = now
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let response: SessionsResponse
        do {
            response = try await client.sessions()
        } catch {
            // Keep whatever is already on screen: a failed refresh should not
            // blank a list the user is reading.
            errorMessage = error.localizedDescription
            return
        }

        let sessions = response.sessions ?? []

        // Prefer the server's clock. Both the recency window and the session
        // timestamps then come from the same source, so phone clock drift cannot
        // age a run out of the list or hold a stale one in.
        let referenceTime = response.serverTime ?? now()

        let liveSessionIDs = sessions.compactMap { session -> String? in
            guard session.isStreaming == true, session.archived != true else { return nil }
            guard let id = session.sessionId, !id.isEmpty else { return nil }
            return id
        }
        let probeIDs = Array(liveSessionIDs.prefix(Self.maximumWaitingProbes))
        didLimitWaitingProbes = probeIDs.count < liveSessionIDs.count

        let awaiting = await awaitingInputSessionIDs(among: probeIDs)

        rows = RunsProjection.rows(
            sessions: sessions,
            awaitingInputSessionIDs: awaiting,
            now: referenceTime,
            recentWindow: recentWindow
        )
    }

    /// Probes the given sessions concurrently.
    ///
    /// A probe that throws is treated as "not known to be waiting" rather than
    /// failing the whole refresh: the run still appears as `running`, which is
    /// true. Reporting `waiting` on a failed probe would be inventing state.
    private func awaitingInputSessionIDs(among sessionIDs: [String]) async -> Set<String> {
        guard !sessionIDs.isEmpty else { return [] }
        let client = self.client

        return await withTaskGroup(of: String?.self) { group in
            for sessionID in sessionIDs {
                group.addTask {
                    if let approval = try? await client.approvalPending(sessionID: sessionID),
                       approval.pending != nil || (approval.pendingCount ?? 0) > 0 {
                        return sessionID
                    }
                    if let clarification = try? await client.clarifyPending(sessionID: sessionID),
                       clarification.pending != nil || (clarification.pendingCount ?? 0) > 0 {
                        return sessionID
                    }
                    return nil
                }
            }

            var awaiting: Set<String> = []
            for await sessionID in group {
                if let sessionID { awaiting.insert(sessionID) }
            }
            return awaiting
        }
    }
}
