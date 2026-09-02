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
/// Work stays behind a flag so it can be turned off, but the **owner enabled it
/// by default** on 2026-08-30 once Runs, the Work shell and the Now header were
/// all landed and tested. Board is still honest about not being wired (Phase 3).
///
/// Every call site must read `defaultIsEnabled` rather than writing a literal —
/// two `@AppStorage` declarations with different defaults would disagree about
/// what "unset" means.
enum WorkFeature {
    static let isEnabledKey = "work.isEnabled"
    static let lastSegmentKey = "work.lastSegment"

    /// Value used when nothing is stored. `@AppStorage` resolves "unset" at each
    /// declaration, so this constant is the one place it is decided.
    static let defaultIsEnabled = true

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
