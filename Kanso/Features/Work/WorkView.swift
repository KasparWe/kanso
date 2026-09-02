import SwiftUI

/// Work destination: Runs, Board, Schedules (Phase 2 of `ROADMAP.md`).
///
/// Deliberately restrained per `PRODUCT.md`: no glass or blur behind a scrolling
/// list, status carried by text **and** icon rather than colour alone, and no
/// state shown that the server cannot substantiate.
struct WorkView: View {
    let server: URL
    let onAPIError: (Error) -> Void

    @AppStorage(WorkFeature.lastSegmentKey) private var storedSegmentRawValue = WorkFeature.defaultSegment.rawValue
    @State private var segment: WorkSegment = WorkFeature.defaultSegment
    @State private var runsViewModel: RunsViewModel
    @State private var hasAppliedOpeningSegment = false

    init(server: URL, onAPIError: @escaping (Error) -> Void) {
        self.server = server
        self.onAPIError = onAPIError
        _runsViewModel = State(initialValue: RunsViewModel(client: APIClient(baseURL: server)))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Work", selection: $segment) {
                ForEach(WorkSegment.allCases) { segment in
                    Text(segment.title).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            switch segment {
            case .runs:
                RunsListView(viewModel: runsViewModel)
            case .board:
                boardPlaceholder
            case .schedules:
                TasksView(server: server, onAPIError: onAPIError)
            }
        }
        .navigationTitle(String(localized: "Work"))
        .onAppear {
            guard !hasAppliedOpeningSegment else { return }
            hasAppliedOpeningSegment = true
            segment = WorkFeature.storedSegment(storedSegmentRawValue)
        }
        .onChange(of: segment) { _, newSegment in
            storedSegmentRawValue = newSegment.rawValue
        }
        .task {
            await runsViewModel.load()
            // Attention beats habit: an approval waiting on the human wins over
            // the remembered segment (PRODUCT.md).
            if runsViewModel.rows.contains(where: { $0.lifecycle == .waitingForYou }) {
                segment = .runs
            }
        }
    }

    /// Board is not wired to a real server board yet. Promoting the Kanban lab is
    /// Phase 3 and gated on contract plus owner validation, so this states the
    /// situation instead of rendering an empty board that looks broken.
    private var boardPlaceholder: some View {
        ContentUnavailableView {
            Label(String(localized: "Board is not enabled yet"), systemImage: "rectangle.3.group")
        } description: {
            Text(String(localized: "Kanban is still a lab feature. It moves here once its server contract is validated."))
        }
    }
}

/// Runs list. Groups by lifecycle so the most urgent work is first, matching the
/// order `RunLifecycle.attentionRank` defines.
private struct RunsListView: View {
    let viewModel: RunsViewModel

    var body: some View {
        List {
            if viewModel.didLimitWaitingProbes {
                Section {
                    Label(
                        String(localized: "Many runs are live — some may be waiting for you without showing it here."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            ForEach(orderedLifecycles, id: \.self) { lifecycle in
                let rows = viewModel.rows.filter { $0.lifecycle == lifecycle }
                if !rows.isEmpty {
                    Section(sectionTitle(for: lifecycle)) {
                        ForEach(rows) { row in
                            RunRowView(row: row)
                        }
                    }
                }
            }

            if viewModel.rows.isEmpty, !viewModel.isLoading {
                Section {
                    Text(String(localized: "Nothing is running right now."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.load() }
        .overlay {
            if viewModel.isLoading, viewModel.rows.isEmpty {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
    }

    private var orderedLifecycles: [RunLifecycle] {
        RunLifecycle.allCases.sorted { $0.attentionRank < $1.attentionRank }
    }

    private func sectionTitle(for lifecycle: RunLifecycle) -> String {
        switch lifecycle {
        case .waitingForYou: String(localized: "Waiting for you")
        case .running: String(localized: "Running")
        // Not "Completed": the server exposes no success or failure signal, so
        // all we can honestly claim is recent activity.
        case .recentlyActive: String(localized: "Recently active")
        }
    }
}

private struct RunRowView: View {
    let row: RunRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title)
                .font(.body)
                .lineLimit(2)

            HStack(spacing: 6) {
                // Icon *and* text: colour alone must never carry state.
                Label(statusText, systemImage: statusSymbol)
                    .labelStyle(.titleAndIcon)

                if let profile = row.profile {
                    Text("· \(profile)")
                }
                if row.isReadOnly {
                    Text("· \(String(localized: "Read only"))")
                }
                if let activity = row.lastActivityAt {
                    Text("· \(relativeDescription(activity))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(statusText)")
    }

    private var statusText: String {
        switch row.lifecycle {
        case .waitingForYou: String(localized: "Waiting for you")
        case .running: String(localized: "Running")
        case .recentlyActive: String(localized: "Recently active")
        }
    }

    private var statusSymbol: String {
        switch row.lifecycle {
        case .waitingForYou: "person.crop.circle.badge.questionmark"
        case .running: "arrow.triangle.2.circlepath"
        case .recentlyActive: "clock"
        }
    }

    private func relativeDescription(_ timestamp: Double) -> String {
        Date(timeIntervalSince1970: timestamp)
            .formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }
}
