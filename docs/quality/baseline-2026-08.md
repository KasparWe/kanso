# Baseline defect ledger — August 2026

Phase 0 evidence ledger for the Kanso fork. Its purpose is to convert "the app is buggy"
into reproducible, prioritized, layer-attributed evidence **before** any fix is written.

## Status of this ledger

### Automated baseline: GREEN (2026-08-28)

Toolchain installed and the suite runs clean on an unmodified `master`:

```
Xcode 26.6 (17F113) · iOS 26.5 simulator runtime (23F77) · iPhone 17, arm64

xcodebuild build-for-testing   → ** TEST BUILD SUCCEEDED **   exit 0, 136s, 0 errors
xcodebuild test-without-building → result "Passed"            exit 0, 97s

  passedTests  1665
  failedTests     0
  skippedTests    2
  121 distinct test suites
```

The 2 skips are `TranscriptMediaPreviewViewModelTests` Photo Library **integration**
tests (`testSaveVideoFileToPhotoLibraryIntegration`,
`testInvalidVideoIsRejectedByPhotoLibraryIntegration`) — they need real Photos access a
simulator cannot provide. Environment skips, not failures.

Build produced **279 warnings**. That is upstream's inherited baseline, not a regression;
untouched deliberately.

### Progress

| Entry | Verdict |
|---|---|
| P0-1 · long-stream unresponsiveness | **FIXED** — reproduced by measurement, fixed, regression test added |
| P0-2 · stale Live Activity | **NOT FIXABLE APP-SIDE** — Phase 2 push dependency |
| P0-3 · title leaks into transcript | **NOT APP-LAYER** — Agent; needs live SSE capture |
| P0-4 · Kanban board reset | `REPORTED` |
| P0-5 · stale auth after URL/header edit | `REPORTED` |
| P1-1 · dictation 60 s cutoff | `REPORTED` |
| P1-2 · unbounded draft attachments | `REPORTED` |

P0-5, P1-1 and P1-2 remain `REPORTED` and are **not reproduced**. A green unit suite does not
reproduce them: each is a runtime, lifecycle, or performance defect the unit tests never
exercise — which was itself the finding, since 1665 passing tests coexisted with all of
them. Do not fix a `REPORTED` entry before reproducing it.

Suite is now **1669 passed / 0 failed / 2 skipped** (three tests from P0-1, one from P0-4).

Phase 0 gate: the signed simulator install is **done** (Team ID `H55GUGZRDX`, app installs
and launches as `app.kanso`). Only the **live server smoke** remains, which needs the
owner's cookie jar.

**Baseline reference:** `master` = `origin/master` = `upstream/master` = `b4f26bf`,
zero divergence. WebUI pins: tested `f1d399b4`, triaged `4b390e11`.

## Verdict vocabulary

| Verdict | Meaning |
|---|---|
| `REPORTED` | Filed upstream; not observed here |
| `REPRODUCED` | Observed here, with recorded evidence |
| `NOT REPRODUCED` | Attempted here against the pinned server; did not occur |
| `FIXED` | Corrected, with a regression test that fails without the fix |

## Layer attribution

Every entry must name a suspected layer before a fix is attempted: **App** (Swift),
**WebUI** (`hermes-webui` API surface), **Agent** (Hermes Agent: cron, Kanban, tools),
**Proxy**, or **Provider**. A mobile symptom is not automatically an app defect.
Per `AGENTS.md`, contribute upstream when the root cause is not app-layer.

## P0 — Correctness and blocking usability

### P0-1 · Long streaming assistant messages make the app unresponsive

- **Verdict:** `FIXED` (2026-08-29, commit `472f879`) for the single-long-message half.
  The eager-transcript-rows half stays open upstream as #32 / PR #33.
- **Confirmed then fixed.** Upstream issue: [#291](https://github.com/uzairansaruzi/hermex/issues/291)

#### Measured root cause

`appendAssistantToken` ran **once per token** and eagerly built
`flushedContent + pendingAssistantTokenChunks.joined()` to pass to
`deduplicatedReplayToken` as a replay-dedup precheck. That callee returns immediately
unless `isActiveStreamReplayConnection` is true — so on every **normal** stream the app
copied the entire accumulated message per token, on the main actor, then discarded it.
`appendReasoning` had the identical defect via `deduplicatedReplayText`.

Measured on iPhone 17 / iOS 26.5 before the fix:

| Path | 4 000 tokens | 8 000 tokens | Ratio |
|---|---|---|---|
| Assistant | 120.2 ms | 483.7 ms | **4.02x** |
| Reasoning | 130.7 ms | 448.8 ms | **3.43x** |

2.0 is linear, 4.0 is quadratic. After the fix the assistant test runs in 0.027 s
(from 1.428 s) and the reasoning test in 0.059 s (from 0.615 s).

#### Fix

Both `existingContent` parameters became `@autoclosure`, so the expression is evaluated
only when a replay connection needs it. The guards were **split** rather than combined,
because `resetActiveStreamReplayTokenState()` and `matchedPrefixLength = 0` are real
side effects on the early-return paths, not just exits.

#### Process note worth keeping

The first version of the test **passed against the broken code** — an absolute 500 ms
budget, while the quadratic path takes only ~450 ms for 8 k tokens on an M-series Mac.
Had the fix been written first, that green test would have "confirmed" it while being
incapable of ever catching a regression. The test now asserts a **scaling ratio**, which
is machine-independent: slower hardware inflates both measurements equally.

These are the repository's **first performance tests**. Nothing in the 1665 existing
tests could catch this class of defect, which is why the bug survived.

- **Superseded original analysis** — kept because it shows how upstream's own framing
  differed from the measured cause:
- **Layer:** App
- **Expected:** a long streaming response stays scrollable and responsive; render work
  per token is bounded.
- **Observed (upstream):** the app feels progressively slower or temporarily
  unresponsive while a long response streams, worst with substantial Markdown, code,
  tables, tool output, or reasoning. The app can look stalled while the stream is still
  live.
- **Upstream root-cause analysis** (against `b1605f9`, one commit before our baseline)
  separates two costs:
  1. **Many transcript rows** — `ChatTranscriptView.swift:208` wraps the transcript
     `ForEach` in an eager `VStack`, realizing all loaded rows. Tracked separately
     upstream as #32 with open PR #33.
  2. **One long message while growing** — the streaming renderer repeatedly reprocesses
     the accumulated string, and the view model repeatedly joins pending token chunks.
     This is #291's focus.
- **Verified statically on our baseline `b4f26bf`** (2026-08-27, no build — code reading only):
  - `ChatTranscriptView.swift:208` does use `VStack(spacing: transcriptMessageSpacing)`.
    Line number and construct match upstream's report exactly. It is the only
    `VStack(spacing:` in the file and there is no `LazyVStack` anywhere in it.
  - A partial mitigation is **already present**: the `ForEach` scopes live-streaming
    state to the anchor row and wraps rows in `.equatable()`, so non-streaming rows are
    documented as skipping markdown-heavy body re-evaluation on each ~16 ms flush. Any
    fix must not undo this.
  - `MarkdownRenderer.swift` is **1336 lines** and holds two layout paths:
    `MarkdownMathLayoutCache.layout(for:)` at line 54 (cached) and
    `MarkdownMathLayoutCache.uncachedLayout(for: displayedContent)` at line 121.
    The second is the streaming path deliberately bypassing the cache — the most likely
    hot spot.
  - Upstream confirms #260/#261 (merged `53862c4`) improved only the **settled**
    markdown path and "deliberately does not cache changing streaming strings," so that
    work does not address this report.
  - `StreamingWordDrain.swift` is small (79 lines): `unitCount(in:)`,
    `splitAtUnitBoundary(_:unitCount:)`, `drainQuota(...)`.
- **Upstream PR #33 is still OPEN, not merged** (branch
  `issue/32-transcript-lazy-stack`, title "perf(chat): lazily render transcript rows");
  issue #32 is also still open. The eager-row half is therefore **not** fixed upstream.
  Decide deliberately whether to wait for #33, adopt it, or scope this fix to the
  single-message path only.
- **Reproduction here:** DONE by measurement — see the table above. A physical-device
  profile is still worth doing for the *rendering* half (#32/#33), which these tests do
  not cover.
- **Files in scope:** `Features/Chat/ChatTranscriptView.swift`,
  `Features/Chat/MarkdownRenderer.swift`, `Features/Chat/StreamingWordDrain.swift`,
  `Features/Chat/ChatViewModel.swift`, `Features/Chat/ChatStreamCoordinator.swift`
- **Upstream constraints a fix must respect** (from #291's Non-goals and Scope):
  no API or SSE contract changes; no `hermes-webui` changes; no new dependencies; no
  visual redesign of Markdown or the transcript; no Markdown features removed to improve
  a benchmark; no reduction of user-visible message page size without product agreement.
  A fix must **not** silently remove the `.sizeChanges` scroll anchor and must not
  regress the opening/streaming scroll behavior fixed by #137.
- **Upstream's prescribed order:** (1) add deterministic pure performance/regression
  coverage for long streaming Markdown and pending token buffering; (2) measure against
  plain-Markdown, fenced-code, table, list, math, and tool-heavy fixtures; (3) keep
  completed blocks and their parsed representation stable while only the active tail
  changes. Steps 1 and 2 are now unblocked.
- **Notes:** upstream #291's summary emphasises the Markdown renderer reprocessing the
  accumulated string and the view model joining pending chunks in the *drain tick*. The
  measured dominant cost was neither: it was the **dedup precheck in the append path**.
  `drainStreamingContentTick`'s `unitCount(in: pendingAssistantTokenChunks.joined())`
  operates on the bounded pending buffer, so it is not the quadratic term. Worth
  reporting back upstream.

### P0-2 · Live Activity does not reach Completed while backgrounded

- **Verdict:** `NOT FIXABLE APP-SIDE` — reclassified 2026-08-29 from a Phase 1 bug to a
  **Phase 2 push dependency**. Upstream [#290](https://github.com/uzairansaruzi/hermex/issues/290)
- **Layer:** neither App nor WebUI — a missing **capability** (ActivityKit push).
- **Expected:** a run that finishes while the app is backgrounded updates its Live
  Activity to Completed.
- **Observed (upstream):** the Live Activity can remain stale in the background.

#### Why no app-side fix exists

Verified by code reading on our baseline:

- `AgentLiveActivityManager.swift:354` requests the activity with **`pushType: nil`**, so
  ActivityKit cannot deliver updates from outside the app. Nothing external can move the
  activity to Completed.
- While iOS has the app suspended, the SSE connection is dead and no app code runs, so
  the terminal `done` event that calls `end(status:activity:errorSummary:)` never arrives.
- `end(...)` itself is correct: it cancels the pending throttled update, applies the final
  state, and `endActivity` calls `update(finalState)` *before* its 600 ms completion sleep,
  so the final content lands even if the sleep is cut short.
- Foreground reconciliation already exists and is wired up — `ContentView.swift:37` runs
  `reconcileOrphanedLiveActivities` on `scenePhase == .active` and on appear, via
  `LiveActivityReconciler`, with broad coverage in `LiveActivityTests.swift`. An initial
  hypothesis that this was dead code was **wrong**; it is live and tested.
- The stale window is a deliberate upstream tradeoff (#246):
  `staleDate(for:)` at `AgentLiveActivityManager.swift:471` returns
  `Date() + 300s` while running and `+ 90s` once already stale, specifically so a
  suspended run is not dimmed within seconds. That choice directly widens the window in
  which #290's symptom is visible — the two issues are in tension, not independent.

#### The actual fix

`pushType: .token`, plus a server that sends ActivityKit push updates over APNs — i.e.
the Phase 2 Mobile Bridge. Until then the honest behaviour is what ships today: the
activity looks current for up to 5 minutes, then dims, and is corrected on next
foreground.

**Do not attempt a Phase 1 patch here.** Options short of push (a `BGProcessingTask` wake,
or shortening the stale window) either cannot be relied on or regress #246.

- **Consequence for ROADMAP:** Phase 2's notification gate should explicitly include
  ending a Live Activity via push, not only delivering a notification.

### P0-3 · Auto-generated session title appears as extra assistant text

- **Verdict:** `NOT APP-LAYER` (attributed 2026-08-29) — upstream [#288](https://github.com/uzairansaruzi/hermex/issues/288)
- **Layer:** **Agent** (or server-side message storage) — *not* App, *not* WebUI.
- **Expected:** the generated title updates the session title only.
- **Observed (upstream):** the title also renders as assistant transcript text after a
  response.

#### Attribution evidence

- **App handling is correct.** `SSEClient.swift:254` parses a *distinct* `"title"` SSE
  event into `.title(TitleStreamEvent)`. `ChatStreamCoordinator.swift:471` routes it to
  `streamCoordinatorUpdateTitle(payload)` only — it is never appended to message content.
  (`ChatViewModel.swift:2504` also matches `case .title` but is the unrelated `/title`
  slash command.)
- **WebUI does not author the event vocabulary.** `_handle_sse_stream`
  (`api/routes.py:5997`, pinned `f1d399b4`) is a pass-through: it pulls `(event, data)`
  off a subscriber queue and forwards each one via `_sse_with_id`. There is no title
  emission in the streaming path.
- The only title generation found in webui is `title_from(s.messages, s.title)` at
  `api/routes.py:8076`, on the **non-streaming** `/api/chat` path. It derives a title from
  existing messages rather than making a model call, so it cannot emit tokens.

Therefore the title text reaching the transcript as assistant content must originate
either (a) upstream of webui, in whatever publishes to the stream queue — the Hermes
Agent, whose source is not available locally — or (b) in the server's stored `messages`,
which the app would then render faithfully after its post-`done` transcript reload.

#### What is needed to finish this

Live reproduction against the owner's server, capturing the raw SSE frames, to
distinguish (a) from (b). **Blocked on the smoke-test cookie jar.** Per `AGENTS.md`, if
confirmed non-app-layer this should be reported upstream rather than patched here. A
defensive app-side filter is possible but would mask a server defect, so it should not be
written before attribution is complete.

### P0-4 · Kanban silently resets the locally browsed Board after relaunch

- **Verdict:** `FIXED` (2026-08-30, commit `f12f368`) — upstream [#259](https://github.com/uzairansaruzi/hermex/issues/259)
- **Layer:** App

#### Root cause

`selectedBoardSlug` had **no persistence anywhere in the Kanban feature** — no
`UserDefaults`, no `@AppStorage`, no SwiftData. `load()` read
`previouslySelectedBoard` from that same in-memory value, so after relaunch it was
`nil` and `previouslySelectedBoard ?? currentBoard` fell back to the server's active
Board.

#### Fix

New `KanbanBoardSelectionStore` persists the slug per server, keyed by absolute URL,
mirroring `SessionRowDisplaySettings.showCliSessionsKey(for:)`. Persisted at the two
genuine selection points only — **not** at the `selectedBoardSlug = nil` inside the broad
teardown, since a reset must not forget the user's choice.

#### Two mistakes worth remembering

1. The first test selected `"release"` against the default `KanbanFixtures.boards`, which
   holds only `"main"`. `selectBoard()` rejects a slug absent from `boards`, so the call
   was a **no-op and the test never exercised the fix**. Use `KanbanFixtures.multiBoards`.
2. Persisting inside `load()` made the existing Kanban suites **order-dependent** — most
   share `https://example.test`, so one test's selection leaked into the next test's
   `load()` and broke five previously passing tests. Both Kanban test classes now clear
   persisted selections in `setUp`/`tearDown`. **Any future per-server persistence needs
   the same isolation.**

Verified red/green by stashing the production wiring: fails (rc 65) without it, passes
with it. Full suite 1669 / 0 / 2.
- **Expected:** the selected board survives relaunch; the active board never changes
  without user action.
- **Observed (upstream):** relaunch silently resets the browsed board.
- **Impact:** violates Product Principle 7 and the Phase 3 requirement that no silent
  active-board change occurs.
- **Reproduction here:** pending.

### P0-5 · Onboarding keeps stale auth status after server URL or header edits

- **Verdict:** `REPORTED` — upstream [#285](https://github.com/uzairansaruzi/hermex/issues/285)
- **Layer:** App
- **Expected:** editing the server URL or auth headers invalidates the previous auth
  result.
- **Observed (upstream):** stale auth status persists.
- **Impact:** blocks the Phase 5 gate that a new tester recovers from a wrong URL and an
  auth failure. Also affects the owner's own multi-server isolation testing.
- **Reproduction here:** pending.

## P1 — Core usability

### P1-1 · Server-First dictation auto-stops and transcribes after 60 seconds

- **Verdict:** `REPORTED` — upstream [#273](https://github.com/uzairansaruzi/hermex/issues/273),
  labelled `bug`, `ready-for-agent`, `needs-manual-validation`, `area:voice`
- **Layer:** App (suspected)
- **Impact:** voice capture is the Phase 4 prerequisite that must be dependable before
  voice conversation ships. A hard 60-second ceiling makes it unreliable for real dictation.
- **Reproduction here:** pending; requires a physical device microphone.

### P1-2 · Retained draft-attachment storage is unbounded

- **Verdict:** `REPORTED` — upstream [#300](https://github.com/uzairansaruzi/hermex/issues/300)
- **Layer:** App
- **Impact:** matches the Phase 1 requirement to bound replay journals, metering events,
  snapshots, and cached attachments. Unbounded on-device growth on the owner's daily
  driver.
- **Reproduction here:** pending.

## Unverified areas with no upstream report

These are **untested**, not known-good. Each needs a first pass once the toolchain
exists, per the Phase 0 smoke list.

| Area | Scenario to run |
|---|---|
| Auth | Login, token persistence, multi-server isolation |
| Sessions | Session list load, pagination, session switching under load |
| Chat | Normal chat, reconnect mid-stream, cancel, error recovery |
| Attachments | Image upload, file upload, paste, Share Extension |
| Cron | List, create, edit, Run Now, Pause/Resume, output navigation |
| Kanban | Contract compatibility against the pinned WebUI, board load |
| Background | Background/foreground, lock, force-quit, network loss, Wi-Fi ↔ cellular |
| Accessibility | Dynamic Type, VoiceOver, Reduce Motion, light/dark |

## Upstream context worth tracking, not defects

- Voice programme #248–#257: a staged state-machine, audio, caption, and TTS series.
  Phase 4 should build on these slices rather than reimplementing voice.
- Feature proposals #262 (transcript rework), #271 (voice-first composer),
  #275 (saved prompts), #279 (session states, Projects, worktrees), #297 (native OIDC).
  Relevant to product direction; not baseline defects.

## Procedure for adding an entry

1. Verify server health and app/server version compatibility. Never log secrets.
2. Record: expected, observed, exact reproduction steps, environment (app commit,
   WebUI commit, iOS version, device or simulator), screenshot or log reference,
   suspected layer, severity.
3. Attribute the layer before proposing a fix.
4. Do not patch while auditing. Finish the evidence list first.
5. Review with the owner, then fix exactly one selected defect, test-first.
