import Foundation

/// The three Work destinations from `PRODUCT.md`.
///
/// Raw values are persisted, so they are stable identifiers and must not be
/// renamed to change a label — `title` carries the user-facing text.
enum WorkSegment: String, CaseIterable, Identifiable, Sendable {
    case runs
    case board
    case schedules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runs: String(localized: "Runs")
        case .board: String(localized: "Board")
        case .schedules: String(localized: "Schedules")
        }
    }
}

/// Storage and gating for the Work destination (Phase 2 of `ROADMAP.md`).
///
/// Work is behind a flag defaulting to **off**: the release policy requires
/// incomplete Home/Work work to stay invisible, so an unfinished destination
/// cannot disrupt daily use of the app.
enum WorkFeature {
    static let isEnabledKey = "work.isEnabled"
    static let lastSegmentKey = "work.lastSegment"

    /// Default when nothing is stored. `PRODUCT.md` puts Runs first because it
    /// answers "what is happening right now?", which is the reason to open Work.
    static let defaultSegment: WorkSegment = .runs

    /// Segment stored under `lastSegmentKey`, falling back to the default.
    ///
    /// An unknown raw value — a segment removed in a later build, or corrupt
    /// defaults — falls back rather than crashing or showing nothing.
    static func storedSegment(_ rawValue: String?) -> WorkSegment {
        guard let rawValue, let segment = WorkSegment(rawValue: rawValue) else {
            return defaultSegment
        }
        return segment
    }

    /// Segment Work should open on.
    ///
    /// A pending approval or clarification overrides the remembered choice:
    /// `PRODUCT.md` states that if an approval is pending, Work opens directly to
    /// the affected run. Attention beats habit.
    static func openingSegment(
        remembered: WorkSegment,
        hasWaitingRun: Bool
    ) -> WorkSegment {
        hasWaitingRun ? .runs : remembered
    }
}
