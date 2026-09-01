import SwiftUI
import SwiftData

struct KansoSceneActions {
    let canCreateNewChat: Bool
    let createNewChat: () -> Void
    let searchSessions: () -> Void
}

private struct KansoSceneActionsKey: FocusedValueKey {
    typealias Value = KansoSceneActions
}

extension FocusedValues {
    var hermexSceneActions: KansoSceneActions? {
        get { self[KansoSceneActionsKey.self] }
        set { self[KansoSceneActionsKey.self] = newValue }
    }
}

struct KansoCommands: Commands {
    @FocusedValue(\.hermexSceneActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                actions?.createNewChat()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(actions?.canCreateNewChat != true)
        }

        CommandGroup(after: .newItem) {
            Button("Search Sessions") {
                actions?.searchSessions()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions == nil)
        }
    }
}

@main
struct HermesMobileApp: App {
    @State private var authManager = AuthManager()
    @AppStorage(AppTheme.storageKey) private var appThemeRawValue = AppTheme.system.rawValue

    #if DEBUG
    /// Server URL passed after `--work`, if that launch argument is present.
    private static var workPreviewServer: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--work") else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return URL(string: "https://work.preview.invalid") }
        return URL(string: arguments[next]) ?? URL(string: "https://work.preview.invalid")
    }
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Launch argument hook so the Streaming Lab can be opened without
            // UI navigation (agent-driven simulator diagnosis, issue #234):
            // `xcrun simctl launch <udid> com.uzairansar.hermesmobile --streaming-lab`
            if ProcessInfo.processInfo.arguments.contains("--streaming-lab") {
                NavigationStack {
                    StreamingLabView()
                }
            } else if let workServer = Self.workPreviewServer {
                // Same hook as the Streaming Lab: opens Work directly so it can be
                // inspected in the simulator without navigating or signing in.
                // `--work https://host` (issue #279 groundwork, Phase 2).
                NavigationStack {
                    WorkView(server: workServer, onAPIError: { _ in })
                }
                .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
            } else {
                ContentView(authManager: authManager)
                    .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
            }
            #else
            ContentView(authManager: authManager)
                .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
            #endif
        }
        .modelContainer(for: [CachedSession.self, CachedMessage.self])
        .commands {
            KansoCommands()
            SidebarCommands()
        }
    }
}
