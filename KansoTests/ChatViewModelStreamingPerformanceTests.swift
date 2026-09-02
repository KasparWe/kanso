import SwiftUI
import XCTest
@testable import Kanso

/// Streaming append-path complexity tests for issue #291 (long streaming assistant
/// messages make the app unresponsive).
///
/// These are the repository's first performance regression tests, so the design is
/// deliberately conservative about flakiness:
///
/// - They exercise only the **synchronous append path**. `emit` runs on the main
///   actor and the test never awaits inside the emit loop, so the coalesced flush
///   task cannot interleave. That removes cadence timing from the measurement.
/// - They assert a **scaling ratio**, not an absolute duration. Both runs happen
///   back to back on the same machine, so the ratio is machine-independent: a
///   slower CI runner inflates both measurements equally and the ratio is
///   unchanged. An absolute budget was tried first and rejected — on an M-series
///   Mac the quadratic implementation takes only ~450ms for 8k tokens, so any
///   budget loose enough to be safe on slow hardware also passes the bug.
/// - Absolute durations are reported in the failure message for diagnosis.
///
/// What they pin down: appending N streamed tokens must cost O(N) overall, not
/// O(N²). The regression they guard against is reconstructing the whole accumulated
/// message once per token — `flushedContent + pendingChunks.joined()` — to feed a
/// replay-dedup precheck that is inert unless the connection is a replay connection.
final class ChatViewModelStreamingPerformanceTests: XCTestCase {
    /// Tokens per measured run. Large enough that a quadratic implementation is
    /// unambiguously slow, small enough to stay a fast unit test when linear.
    private let tokenCount = 8_000

    /// Maximum tolerated ratio of `time(2N) / time(N)`.
    ///
    /// Perfectly linear work gives 2.0; quadratic work gives 4.0. Measured on the
    /// pre-fix implementation: 3.69 for the assistant path (123.0ms → 453.5ms) and
    /// 3.02 for the reasoning path (158.1ms → 477.7ms). 2.6 sits clearly above
    /// linear-plus-noise and clearly below both observed quadratic values.
    private let maximumScalingRatio = 2.6

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    func testAppendingManyAssistantTokensStaysLinear() async throws {
        let half = try await measureAppendNanoseconds(
            tokenCount: tokenCount / 2,
            emit: { client, index in client.emit(.token("token\(index) ")) }
        )
        let full = try await measureAppendNanoseconds(
            tokenCount: tokenCount,
            emit: { client, index in client.emit(.token("token\(index) ")) }
        )

        let ratio = scalingRatio(full: full, half: half)
        XCTAssertLessThan(
            ratio,
            maximumScalingRatio,
            """
            Appending assistant tokens scaled at \(String(format: "%.2f", ratio))x when the count \
            doubled (~2.0 is linear, ~4.0 is quadratic; limit \(maximumScalingRatio)). \
            \(tokenCount / 2) took \(millisecondsDescription(half)), \
            \(tokenCount) took \(millisecondsDescription(full)). \
            The append path is reconstructing the accumulated message per token.
            """
        )
    }

    @MainActor
    func testAppendingManyReasoningChunksStaysLinear() async throws {
        let half = try await measureAppendNanoseconds(
            tokenCount: tokenCount / 2,
            emit: { client, index in client.emit(.reasoning("step\(index) ")) }
        )
        let full = try await measureAppendNanoseconds(
            tokenCount: tokenCount,
            emit: { client, index in client.emit(.reasoning("step\(index) ")) }
        )

        let ratio = scalingRatio(full: full, half: half)
        XCTAssertLessThan(
            ratio,
            maximumScalingRatio,
            """
            Appending reasoning chunks scaled at \(String(format: "%.2f", ratio))x when the count \
            doubled (~2.0 is linear, ~4.0 is quadratic; limit \(maximumScalingRatio)). \
            \(tokenCount / 2) took \(millisecondsDescription(half)), \
            \(tokenCount) took \(millisecondsDescription(full)). \
            The reasoning append path is reconstructing the accumulated text per chunk.
            """
        )
    }

    /// Appending must remain lossless: pacing and dedup prechecks may not drop or
    /// reorder content. Guards the optimisation against silently skipping tokens.
    @MainActor
    func testEveryAppendedTokenSurvivesToTheTranscript() async throws {
        let streamClient = PerformanceSpySSEStreamingClient()
        let viewModel = try makeViewModel(streamClient: streamClient)
        let didStart = await viewModel.sendMessage("Stream a long reply")
        XCTAssertTrue(didStart)

        let tokens = (0..<200).map { "token\($0) " }
        for token in tokens {
            streamClient.emit(.token(token))
        }
        streamClient.emit(.streamEnd)

        let expected = tokens.joined()
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if assistantContent(of: viewModel) == expected { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(
            assistantContent(of: viewModel),
            expected,
            "every appended token must reach the transcript exactly once, in order"
        )
    }

    // MARK: - Helpers

    @MainActor
    private func measureAppendNanoseconds(
        tokenCount: Int,
        emit: (PerformanceSpySSEStreamingClient, Int) -> Void
    ) async throws -> UInt64 {
        let streamClient = PerformanceSpySSEStreamingClient()
        let viewModel = try makeViewModel(streamClient: streamClient)
        let didStart = await viewModel.sendMessage("Stream a long reply")
        XCTAssertTrue(didStart)

        // Warm the path so first-call costs (lazy globals, allocator growth) are not
        // attributed to the measurement.
        emit(streamClient, -1)

        let start = DispatchTime.now().uptimeNanoseconds
        for index in 0..<tokenCount {
            emit(streamClient, index)
        }
        let end = DispatchTime.now().uptimeNanoseconds

        // Keep the view model alive across the measurement.
        withExtendedLifetime(viewModel) {}
        return end - start
    }

    private func millisecondsDescription(_ nanoseconds: UInt64) -> String {
        String(format: "%.1fms", Double(nanoseconds) / 1_000_000)
    }

    private func scalingRatio(full: UInt64, half: UInt64) -> Double {
        guard half > 0 else { return .infinity }
        return Double(full) / Double(half)
    }

    @MainActor
    private func assistantContent(of viewModel: ChatViewModel) -> String? {
        viewModel.messages.last(where: { $0.role == "assistant" })?.content
    }

    @MainActor
    private func makeViewModel(
        streamClient: PerformanceSpySSEStreamingClient
    ) throws -> ChatViewModel {
        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/chat/start":
                return apiTestJSONResponse(
                    #"{"session_id": "session-abc", "stream_id": "stream-123"}"#,
                    for: request
                )
            default:
                return apiTestJSONResponse(
                    #"{"session": {"session_id": "session-abc", "title": "Perf", "messages": []}}"#,
                    for: request
                )
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let server = try XCTUnwrap(URL(string: "https://example.test"))
        let client = APIClient(baseURL: server, session: urlSession)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let summary = try decoder.decode(
            SessionSummary.self,
            from: Data(
                #"{"session_id": "session-abc", "title": "Perf", "workspace": "/tmp/workspace"}"#.utf8
            )
        )

        // Long coalescing and cadence delays keep the paced flush from interleaving
        // with the synchronous emit loop, so measurements cover the append path only.
        return ChatViewModel(
            session: summary,
            server: server,
            client: client,
            streamClient: streamClient,
            approvalStreamClient: PerformanceSpySSEStreamingClient(),
            clarifyStreamClient: PerformanceSpySSEStreamingClient(),
            streamingScrollCoalescingDelayNanoseconds: 1_000_000,
            streamingWordRevealCadenceNanoseconds: 1_000_000,
            streamingMaxRevealLagNanoseconds: 10_000_000
        )
    }
}

private final class PerformanceSpySSEStreamingClient: SSEStreamingClient {
    private(set) var lastEventID: String?
    private var onEvent: (@MainActor (SSEEvent) -> Void)?

    func start(url: URL, onEvent: @escaping @MainActor (SSEEvent) -> Void) {
        lastEventID = nil
        self.onEvent = onEvent
    }

    func stop() {}

    @MainActor
    func emit(_ event: SSEEvent) {
        onEvent?(event)
    }
}
