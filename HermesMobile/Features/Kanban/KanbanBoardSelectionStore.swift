import Foundation

/// Per-server persistence for the locally browsed Kanban Board (issue #259).
///
/// Board selection is **browse-only** state: `PROJECT_SPEC` requires that it is
/// local to the app and never changes the server's active Board. Because it is
/// local, nothing on the server can restore it after a relaunch — so it has to
/// be remembered here.
///
/// It is scoped per server for the same reason the CLI-sessions toggle is
/// (`SessionRowDisplaySettings.showCliSessionsKey(for:)`): a Board browsed on one
/// server must not appear as the selection on another, and Board slugs are not
/// unique across servers. See `docs/agents/multi-server-state-isolation.md`.
enum KanbanBoardSelectionStore {
    static let storageKeyPrefix = "kanban.selectedBoard"

    /// Storage key for `server`, keyed by its absolute URL to match how the
    /// offline cache and the per-server session-row toggles scope their state.
    static func storageKey(for server: URL) -> String {
        "\(storageKeyPrefix)|\(server.absoluteString)"
    }

    /// The remembered Board slug for `server`, or `nil` when nothing is stored.
    ///
    /// Blank and whitespace-only values are treated as absent: a stored empty
    /// string must not win over the server's default Board.
    static func selectedBoard(for server: URL, defaults: UserDefaults = .standard) -> String? {
        guard let stored = defaults.string(forKey: storageKey(for: server)) else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Remembers `slug` for `server`. Passing `nil` or a blank slug clears the
    /// entry, so callers can forget a removed Board without a separate API.
    static func setSelectedBoard(
        _ slug: String?,
        for server: URL,
        defaults: UserDefaults = .standard
    ) {
        let key = storageKey(for: server)
        guard
            let slug,
            !slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(slug, forKey: key)
    }
}
