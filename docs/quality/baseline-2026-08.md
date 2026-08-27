# Baseline defect ledger — August 2026

Phase 0 evidence ledger for the Kanso fork. Its purpose is to convert "the app is buggy"
into reproducible, prioritized, layer-attributed evidence **before** any fix is written.

## Status of this ledger

**Nothing below has been reproduced on this machine.** As of 2026-08-27 there is no
Apple toolchain installed here:

```
$ xcode-select -p
/Library/Developer/CommandLineTools
$ xcodebuild -version
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools instance
$ xcrun simctl list devices available
xcrun: error: unable to find utility "simctl", not a developer tool or in PATH
```

No simulator runtime exists, no signing identity exists (`security find-identity -v -p
codesigning` → `0 valid identities found`), and the data volume has 6.3 GB free.

Every entry is therefore seeded from **upstream reports**, marked `REPORTED` rather than
`CONFIRMED`. Each must be independently reproduced against the owner's server before it
is treated as a Kanso defect. Do not fix anything from this ledger while it is still
`REPORTED` — profile and reproduce first.

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

- **Verdict:** `REPORTED` — upstream [#291](https://github.com/uzairansaruzi/hermex/issues/291)
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
- **Reproduction here:** pending toolchain. Needs a deterministic large-stream fixture
  plus a physical-device profile before any change. Static confirmation of the construct
  is **not** confirmation of the bottleneck — the plan requires profiling first.
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
  changes. Steps 1 and 2 require the toolchain.
- **Notes:** strongest Phase 1 candidate, and the best-specified issue in this ledger.

### P0-2 · Live Activity does not reach Completed while backgrounded

- **Verdict:** `REPORTED` — upstream [#290](https://github.com/uzairansaruzi/hermex/issues/290)
- **Layer:** App (suspected), possibly WebUI delivery timing
- **Expected:** a run that finishes while the app is backgrounded updates its Live
  Activity to Completed.
- **Observed (upstream):** the Live Activity can remain stale in the background.
- **Impact:** directly contradicts Product Principle 2 — the lock screen would assert a
  run is still going when it is not. Blocks Phase 2's notification gate.
- **Reproduction here:** pending; requires a physical device, not a simulator.

### P0-3 · Auto-generated session title appears as extra assistant text

- **Verdict:** `REPORTED` — upstream [#288](https://github.com/uzairansaruzi/hermex/issues/288)
- **Layer:** App or WebUI — **attribution required before fixing.** If the title arrives
  on the same stream channel as assistant content, the root cause is server-side and
  belongs upstream.
- **Expected:** the generated title updates the session title only.
- **Observed (upstream):** the title also renders as assistant transcript text after a
  response.
- **Reproduction here:** pending.

### P0-4 · Kanban silently resets the locally browsed Board after relaunch

- **Verdict:** `REPORTED` — upstream [#259](https://github.com/uzairansaruzi/hermex/issues/259)
- **Layer:** App
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
