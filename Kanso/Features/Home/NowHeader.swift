import SwiftUI

/// Client surface the Now header needs: the Runs inputs plus cron jobs.
protocol NowDataClient: RunsDataClient {
    func crons() async throws -> CronJobsResponse
}

extension APIClient: NowDataClient {}

/// Backing model for Home's Now header (Phase 2 of `ROADMAP.md`).
///
/// Composes the same `/api/sessions` + pending probes as Runs with `/api/crons`,
/// then defers every ordering and capping decision to `NowSummary`.
@MainActor
@Observable
final class NowViewModel {
    private(set) var items: [NowItem] = []
    private(set) var isLoading = false

    private let client: any NowDataClient
    private let now: @Sendable () -> Double

    init(
        client: any NowDataClient,
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }
    ) {
        self.client = client
        self.now = now
    }

    /// Loads sessions and schedules.
    ///
    /// Either source failing is not an error worth showing: the Now header is
    /// supplementary chrome above the session list, and an error banner there
    /// would be noise next to the list's own error handling. A failed source
    /// simply contributes nothing.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        let sessionsResponse = try? await client.sessions()
        let sessions = sessionsResponse?.sessions ?? []
        let referenceTime = sessionsResponse?.serverTime ?? now()

        // Only live runs can be blocked on input, and probing is one request each
        // (no global pending query) — same bound as RunsViewModel.
        let liveIDs = sessions.compactMap { session -> String? in
            guard session.isStreaming == true, session.archived != true else { return nil }
            guard let id = session.sessionId, !id.isEmpty else { return nil }
            return id
        }.prefix(RunsViewModel.maximumWaitingProbes)

        var awaiting: Set<String> = []
        for sessionID in liveIDs {
            if let approval = try? await client.approvalPending(sessionID: sessionID),
               approval.pending != nil || (approval.pendingCount ?? 0) > 0 {
                awaiting.insert(sessionID)
                continue
            }
            if let clarification = try? await client.clarifyPending(sessionID: sessionID),
               clarification.pending != nil || (clarification.pendingCount ?? 0) > 0 {
                awaiting.insert(sessionID)
            }
        }

        let runs = RunsProjection.rows(
            sessions: sessions,
            awaitingInputSessionIDs: awaiting,
            now: referenceTime
        )
        let schedules = (try? await client.crons())?.jobs ?? []

        items = NowSummary.items(runs: runs, schedules: schedules, now: referenceTime)
    }
}

/// Compact Now header shown above recent conversations.
///
/// Renders nothing when there is nothing to say — an empty "Now" box is worse
/// than no box, and `PRODUCT.md` asks Home to surface attention, not chrome.
struct NowHeaderView: View {
    let viewModel: NowViewModel

    var body: some View {
        if !viewModel.items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Now"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(viewModel.items) { item in
                    NowItemRow(item: item)
                }
            }
            .padding(.vertical, 10)
        }
    }
}

private struct NowItemRow: View {
    let item: NowItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Icon and text both carry the state; colour is never the only signal.
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch item.kind {
        case .waitingRun: "person.crop.circle.badge.questionmark"
        case .failedSchedule: "exclamationmark.triangle"
        case .runningRun: "arrow.triangle.2.circlepath"
        case .recentRun: "clock"
        case .upcomingSchedule: "calendar"
        }
    }
}
