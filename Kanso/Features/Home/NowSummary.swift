import Foundation

/// What a Now item is about, in `PRODUCT.md`'s attention order.
///
/// `PRODUCT.md` lists: approval/clarification → failed → blocked → active →
/// recently completed → upcoming schedule. Two of those are absent here and the
/// reason matters:
///
/// - **blocked** has no source. Blocked is a Kanban card state, and Kanban is not
///   wired to a real board yet (Phase 3).
/// - **failed runs** cannot be detected. A session row carries no error field
///   (see `RunLifecycle`). Failed *schedules* can, because `CronJob` exposes
///   `state` and `lastStatus` — hence `failedSchedule` and no `failedRun`.
enum NowItemKind: String, CaseIterable, Equatable, Sendable {
    case waitingRun
    case failedSchedule
    case runningRun
    case recentRun
    case upcomingSchedule

    var priority: Int {
        switch self {
        case .waitingRun: 0
        case .failedSchedule: 1
        case .runningRun: 2
        case .recentRun: 3
        case .upcomingSchedule: 4
        }
    }
}

struct NowItem: Identifiable, Equatable, Sendable {
    /// Stable across refreshes so SwiftUI does not re-animate an unchanged row.
    /// Prefixed by kind because a session and a cron job could share an id.
    let id: String
    let kind: NowItemKind
    let title: String
    /// Secondary line. Nil when there is nothing true to add.
    let detail: String?
}

/// Builds Home's compact Now header (Phase 2 of `ROADMAP.md`).
///
/// Pure so the priority order and the three-item cap are testable without a
/// server, a simulator, or a view.
enum NowSummary {
    /// `PRODUCT.md`: "Compact Now header, maximum three items." The cap is the
    /// product decision — Home surfaces what needs attention, it is not a second
    /// Work screen.
    static let maximumItems = 3

    static func items(
        runs: [RunRow],
        schedules: [CronJob] = [],
        now: Double
    ) -> [NowItem] {
        var items: [NowItem] = []

        for run in runs where run.lifecycle == .waitingForYou {
            items.append(NowItem(
                id: "waitingRun-\(run.id)",
                kind: .waitingRun,
                title: run.title,
                detail: String(localized: "Waiting for you")
            ))
        }

        for schedule in schedules where needsAttention(schedule) {
            items.append(NowItem(
                id: "failedSchedule-\(schedule.id)",
                kind: .failedSchedule,
                title: schedule.name ?? String(localized: "Schedule"),
                // Prefer the server's own message over a generic label.
                detail: firstNonEmpty(schedule.lastError, schedule.lastDeliveryError)
                    ?? String(localized: "Last run failed")
            ))
        }

        for run in runs where run.lifecycle == .running {
            items.append(NowItem(
                id: "runningRun-\(run.id)",
                kind: .runningRun,
                title: run.title,
                detail: String(localized: "Running")
            ))
        }

        for run in runs where run.lifecycle == .recentlyActive {
            items.append(NowItem(
                id: "recentRun-\(run.id)",
                kind: .recentRun,
                title: run.title,
                // Not "Completed" — no success signal exists.
                detail: String(localized: "Recently active")
            ))
        }

        if let next = nextUpcoming(schedules: schedules, now: now) {
            items.append(NowItem(
                id: "upcomingSchedule-\(next.id)",
                kind: .upcomingSchedule,
                title: next.name ?? String(localized: "Schedule"),
                detail: next.scheduleDisplay
            ))
        }

        // Inputs arrive in attention order already; sorting by priority keeps
        // that guaranteed rather than incidental.
        return items
            .sorted { $0.kind.priority < $1.kind.priority }
            .prefix(maximumItems)
            .map { $0 }
    }

    /// A schedule worth interrupting the user about.
    ///
    /// Deliberately narrow: only the unambiguous error signals. The upstream
    /// WebUI derives a richer set in `_cronStatusMeta` (`static/panels.js`),
    /// including a legacy-broken-recurring heuristic and `schedule_error`. That
    /// derivation lives in the WebUI client rather than the API, so porting it is
    /// a deliberate later step — not something to approximate here. Under-reporting
    /// is the safe direction: a missed warning is recoverable, a false one trains
    /// the user to ignore the header.
    static func needsAttention(_ schedule: CronJob) -> Bool {
        if schedule.state == "error" { return true }
        if schedule.lastStatus == "error" { return true }
        return false
    }

    /// Soonest future run among enabled schedules.
    static func nextUpcoming(schedules: [CronJob], now: Double) -> CronJob? {
        schedules
            .filter { $0.enabled != false && !needsAttention($0) }
            .compactMap { schedule -> (CronJob, Double)? in
                guard let next = schedule.nextRunAt?.date.timeIntervalSince1970 else { return nil }
                guard next >= now else { return nil }
                return (schedule, next)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String? {
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
