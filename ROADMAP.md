# Kanso — Roadmap

Phased plan for the fork. Each phase has an **outcome** and a **gate**. A gate is not
"it compiles" — it is a scenario that must pass end to end, with recorded evidence,
before the next phase starts.

Scope and priority come from [PRODUCT.md](PRODUCT.md). Working agreement and hard rules
come from [AGENTS.md](AGENTS.md). API behavior comes from `PROJECT_SPEC.md`.

## Priorities

1. Cron / background work and Kanban — the headline differentiators.
2. Voice — important, staged.
3. Stable chat and streaming — not the differentiator, but a **release gate** for everything.

## Phase 0 — Fork, identity, baseline, product skeleton

**Outcome:** an owner-controlled fork that builds, tests, installs, connects to the live
server, and can be updated safely.

- [x] Owner-controlled GitHub fork (`KasparWe/kanso`, fork of `uzairansaruzi/hermex`).
- [x] `origin` / `upstream` remotes configured; `upstream` push URL disabled.
- [x] `PRODUCT.md`, `ROADMAP.md`, `docs/adr/0001-fork-and-upstream-strategy.md`.
- [x] `docs/quality/baseline-2026-08.md` ledger opened.
- [ ] Free enough disk for the Apple toolchain.
- [ ] Install full Xcode 26+ and an iOS simulator runtime.
- [ ] `Config/Local.xcconfig` with the owner's Team ID and bundle-ID prefix.
- [ ] Enable Issues and Actions on the fork.
- [ ] Baseline: full XCTest suite green, signed simulator build installs and launches,
      with recorded command output.
- [ ] Live smoke test: login, session list, normal chat, long chat, attachments, cron
      list, Kanban compatibility.
- [ ] Every reproducible defect filed with evidence.
- [ ] `CURRENT.md` handoff (local-only, gitignored).

**Gate:** no feature work until a clean baseline build/test result and a known-defect
ledger both exist.

## Phase 1 — Reliable Core

**Outcome:** chat and run state are dependable enough to underpin everything later.

- Reproduce and fix long-stream UI freezing (upstream #291) — profile before choosing an
  implementation.
- Fix duplicate/incorrect transcript projection, title leakage (#288), stale-session
  application, reconnect loops, and background/foreground reconciliation failures found
  in the baseline.
- Stream chaos tests: connection loss before and after every terminal event, duplicated
  events, out-of-order callbacks, stale async loads, session switching, backgrounding,
  app relaunch.
- Large-stream performance fixtures and an enforced budget.
- Compatibility screen and diagnostics export.
- Contribute server-side root causes upstream; isolate and document any temporary patch.

### Correctness invariants

These are permanent, not phase-scoped:

1. A user send creates at most one server turn.
2. Reconnect never resends the user message.
3. Every event is idempotent via stream/run identity plus sequence or event ID.
4. Switching sessions cannot apply late events to the new session.
5. `done`, `stream_end`, transport close, status poll, and transcript reload cannot
   double-finalize a run.
6. The server transcript is canonical after completion or recovery.
7. The UI always shows one honest state: running, reconnecting, waiting, completed,
   failed, cancelled, or outcome unknown.
8. Draft text and attachments survive recoverable errors.
9. Backgrounding never claims the phone is sustaining server work.
10. Long responses have bounded memory and bounded render work.

**Gate:** a 30-minute physical-device soak with long streams, repeated
background/foreground cycles, network interruption, and session switching — with no
duplicate sends, no transcript corruption, and no unrecoverable stuck state.

## Phase 2 — Home and durable Work

**Outcome:** the app becomes useful for asynchronous work, not only chat.

- Home: Now header plus recent conversations.
- Work shell: Runs, Board, Schedules segments.
- Runs view built from existing session and background state; waiting/failed/completed
  reported truthfully.
- Schedules UX over the existing cron API: grouped list, simple editor, detail, history,
  Run Now, Pause/Resume, error acknowledgement, output and session links.
- Mobile Bridge ADR, then a minimal plugin plus service.
- Private APNs registration, durable event outbox, completion/error/approval
  notifications, exact-session deep links.
- Keep local notifications as fallback; deduplicate local against remote completion alerts.

**Gate:** start a long run and a cron, lock the phone, receive exactly one correct
notification for each, open the exact destination, and recover after bridge, app, and
gateway restarts without duplicate alerts.

## Phase 3 — Excellent mobile Kanban

**Outcome:** agent delegation and review are comfortable from a phone.

- Promote the existing Kanban lab only after contract and owner validation.
- Build Board around Status Focus, not a desktop clone.
- Card create/edit, comments, dependencies, filters, safe transitions, archive/undo,
  live reconciliation.
- Surface Running/Blocked/Waiting in Home and Runs.
- Preview Dispatch, then confirmed Run Dispatcher with spend warning and
  uncertain-outcome reconciliation.
- Multi-board selection persistence; no silent active-board changes (#259).

**Gate:** create, assign, dispatch, monitor, clarify, block/unblock, complete, and review
a card entirely from the phone — including one connection failure — without losing or
misreporting server state.

## Phase 4 — Everyday multimodal and voice

**Outcome:** the app replaces common capture workflows from other assistant apps.

- Harden camera, Photos, Files, paste, and Share Extension input.
- Generated images and files become native artifact cards with Save/Share/Continue.
- Reliable voice capture first.
- Voice conversation mode from upstream's staged state-machine slices (#248–#257);
  interruption only after state correctness.
- App Intents: New Chat, New Voice Chat, Ask from Clipboard, Analyze Photo, Open Work,
  Open Waiting Items.
- Optional EventKit Reminders: selected lists in Home, create/complete, source badges,
  deep links. Kanban and Reminders stay separate internally.

**Gate:** complete a photo-understanding flow, an image-generation flow, a file/share
flow, and a hands-free voice turn on a physical iPhone, with correct interruption and
recovery.

### Candidate: places, routes, and travel planning

Not committed. Captured because it is the owner's strongest live use case — he currently
uses Gemini for travel planning specifically because of its maps and review grounding.

**Key architectural finding (verified against pinned WebUI `f1d399b4`):** the capability
needs **no app release and no fork changes**. `_handle_mcp_tools_list` reads
`cfg.get("mcp_servers", {})`, so MCP servers are Hermes *configuration*. The relevant
endpoints already exist: `/api/mcp/servers`, `/api/mcp/tools`, `/api/session/toolsets`,
plus `/api/skills` and `/api/skills/save`.

Staging, deliberately capability-before-UI:

1. **Config only, no app work.** Add a maps MCP server to the Hermes config. Planning
   works in existing chat, rendered as ordinary tool output. This establishes whether the
   answers are actually competitive with Gemini *before* any UI investment. Verify the
   server's real tool names against `/api/mcp/tools` — never assume them.
2. **Native rendering, only if step 1 proves out.** MapKit place and route cards,
   Open-in-Maps deep links, CoreLocation for "near me", and a multi-stop itinerary as a
   durable run with Live Activity progress. Fits `PRODUCT.md`'s "native results, not
   transcript soup"; multi-step trip planning is a natural fit for the Runs architecture.

Current app-side baseline: **zero** MapKit, CoreLocation, or MCP/toolset surface exists
across the 193 sources. Step 2 is entirely greenfield.

Constraints to resolve before committing:

- **Review licensing is the binding constraint,** not API access. Google Places terms
  restrict caching and redisplay of review content and require attribution — this shapes
  what a native review card may legally show. Apple Maps Server API and OpenStreetMap are
  cheaper but materially weaker on reviews.
- Per-request billing, and the API key lives server-side only — never in the app, never
  in this public repository.
- MapKit and CoreLocation are first-party Apple frameworks, so step 2 does **not** breach
  `AGENTS.md` rule 2 on third-party dependencies.

## Phase 5 — Public self-hoster beta

**Outcome:** another self-hoster can install and understand the app without the owner
operating their machine.

- Distinct public name, icon, privacy copy, support policy.
- Guided server and Mobile Bridge pairing with capability checks.
- Decide hosted push relay versus no remote push for public builds; threat model first.
- Migration and versioning for app cache, bridge data, event envelopes.
- External TestFlight onboarding, feedback capture, compatibility matrix, rollback.
- Published bridge install/upgrade/uninstall documentation.

**Gate:** a new tester completes setup with no developer intervention and recovers from a
wrong URL, an auth failure, an incompatible server, a bridge outage, and a denied
notification permission.

## Release policy

- The integration branch stays green.
- No TestFlight upload without recorded focused tests, full suite, signed simulator
  launch, and the relevant physical-device checks.
- The previous known-good TestFlight build stays available.
- Incomplete Home / Work / Kanban / Bridge work stays behind feature flags.

## Known risks

| Risk | Mitigation |
|---|---|
| Upstream churn in both app and WebUI | Tested pins, capability negotiation, contract tests, deliberate update cadence |
| A mobile symptom may originate in Swift, WebUI, Hermes Agent, proxy, or provider | Require layer-specific evidence before patching |
| Scope explosion into an admin dashboard | Protect the two-destination IA and the phase gates |
| Rich markdown/media overloading SwiftUI mid-stream | Keep rich final rendering off the hot token path |
| A public bundle ID needs maintainer-owned APNs infrastructure | Private BYO credentials now; relay boundary designed for, not built |
| Hosted relay privacy and security | Defer multi-tenancy until threat model, abuse controls, retention, and cost are accepted |
| Reminders/Kanban ownership ambiguity | Unify presentation only, never data |
| Voice is a state-machine product, not a microphone button | Stage it; capture before conversation |
| Branding and licensing | MIT permits the fork; retain copyright and pick distinct public branding before external distribution |
