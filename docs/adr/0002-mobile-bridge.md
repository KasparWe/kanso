# ADR 0002 — Mobile Bridge and push delivery

- **Status:** Proposed
- **Date:** 2026-08-30
- **Deciders:** Repository owner
- **Required by:** `ROADMAP.md` Phase 2 ("Mobile Bridge ADR, then a minimal plugin plus
  service"), and it is the only route to a real fix for ledger entry **P0-2**.

## Context

Two things Kanso needs cannot be built inside the app:

1. **P0-2 — a Live Activity that never reaches Completed while backgrounded.**
   `AgentLiveActivityManager.swift:354` requests the activity with `pushType: nil`, and
   while iOS has the app suspended no app code runs to receive the terminal event. There
   is no app-side fix; see the ledger entry.
2. **Phase 2's notification gate** — being told a long run finished, or that an approval
   is waiting, while the phone is locked.

Both require something outside the app observing server state and pushing to the device.

## Verified constraints

These were checked against the pinned `hermes-webui` (`f1d399b4`) and the owner's live
server on 2026-08-30. **Several contradict the original project plan**, which assumed a
Hermes plugin using documented `on_stream_end` / approval / session-lifecycle hooks.

| Constraint | Evidence |
|---|---|
| **WebUI "extensions" cannot host the bridge.** They serve static files and inject same-origin CSS/JS into the browser shell. No server-side code, no event hooks, no ability to send a push. | `docs/EXTENSIONS.md` — "serve files from one configured local directory", "inject configured same-origin scripts". Explicitly "not a plugin marketplace or dependency system". |
| **No global pending query.** Approvals and clarifications are per-session only. | `_handle_approval_pending` reads `session_id` from the query and looks up a per-session queue (`api/routes.py:6558`). Same for clarify. |
| **No global session event stream.** The gateway SSE is scoped to CLI/gateway sessions and gated on the `show_cli_sessions` setting. | `_handle_gateway_sse_stream` (`api/routes.py:6204`) returns 404 unless `show_cli_sessions`. |
| **Approval/clarify SSE are per-session too.** | Both require `session_id`, else `bad(handler, "session_id is required")`. |
| **No failure signal for runs anywhere.** Not on a session row, not on `/api/session/status`. | `Session.compact()`; `session_status` (`api/session_ops.py:129`). Confirmed live. |
| **Run liveness *is* trustworthy.** `is_streaming` on `/api/sessions` is a live runtime check. | `all_sessions()` passes `include_runtime=True`; `_is_streaming_session` tests membership in `active_stream_ids`. |
| **The app is not provisioned for push at all.** No `aps-environment` entitlement; `UIBackgroundModes` is `["audio"]` only — no `remote-notification`. | `Kanso/Resources/*.entitlements`, `Info.plist`. |

The plan's hook-based design therefore **cannot be built against WebUI**. Any hook-based
approach would have to live in Hermes Agent (`hermes_cli.plugins`, referenced from
`api/commands.py:59`), whose source is not available locally — so its payloads cannot be
confirmed, and `AGENTS.md` rule 1 forbids designing against unverified shapes.

## Decision

Build the bridge as a **standalone service that polls the documented WebUI REST API** and
sends APNs pushes. Not a WebUI extension, not a Hermes Agent plugin.

```
┌──────────┐   REST poll    ┌───────────────┐   APNs    ┌────────┐
│ hermes-  │ ◄───────────── │ mobile-bridge │ ────────► │ iPhone │
│  webui   │                │  (own repo)   │           │ Kanso  │
└──────────┘                └───────────────┘           └────────┘
                              SQLite outbox
                              device registry
```

Rationale: it depends only on endpoints that are **verified to exist and whose shapes are
known** — `/api/sessions`, `/api/crons`, `/api/approval/pending`, `/api/clarify/pending`.
It needs no plugin API, no Agent source, and no WebUI fork. It can be written, tested and
operated entirely independently of upstream's release cadence.

Polling is a deliberate v1 tradeoff, not an oversight: there is no global event stream to
subscribe to. Cost is bounded — one `/api/sessions` call plus one `/api/crons` call per
interval, and pending probes only for sessions where `is_streaming` is true (the same
bound `RunsViewModel` already uses).

### What the bridge does

1. Poll `/api/sessions` and `/api/crons` on an interval (start at 30 s).
2. Detect **transitions**, not states — a run that was streaming and no longer is; an
   approval that appeared; a cron whose `last_status` became `error`.
3. Deduplicate against a SQLite outbox keyed by `(device, event kind, subject id,
   transition)`, so a restart cannot re-notify.
4. Send APNs, retry with backoff, and drop tokens APNs reports invalid.
5. Send **generic text by default**; transcript previews require explicit opt-in.

### What the app must change

- Add the `aps-environment` entitlement and `remote-notification` to `UIBackgroundModes`.
- Register for remote notifications and hand the token to the bridge over an
  authenticated pairing endpoint; store the bridge credential in the Keychain.
- Request the Live Activity with `pushType: .token` and forward the ActivityKit push
  token. **This is the actual P0-2 fix** — it lets the activity be completed from outside
  the app.
- Deduplicate remote notifications against the existing local ones
  (`AppTheme.swift:504`), or the owner gets two alerts per completion.

### Boundaries

- APNs `.p8`, Team ID and Key ID live only in the bridge's own secrets. Never in this
  repo, which is public.
- The bridge is single-tenant. A hosted multi-tenant relay for public App Store builds is
  Phase 5 and needs its own threat model; the event envelope should be versioned so that
  can be added without changing app navigation.

## Consequences

**Positive** — depends only on verified endpoints; independent of upstream churn; no fork;
testable without Apple infrastructure (APNs can be stubbed); unblocks P0-2 and Phase 2's
gate.

**Negative** — polling means notification latency up to one interval, and it cannot see
anything the REST API does not expose. In particular **run failure still cannot be
reported**, because no endpoint carries it; the bridge can say "finished", not "failed".
Two more moving parts to operate (service + APNs key). Push adds an entitlement, which
means the App ID must be reconfigured in the Apple Developer portal.

## Alternatives rejected

| Alternative | Why |
|---|---|
| WebUI extension | Browser-side only. Cannot run server code or send pushes. |
| Hermes Agent plugin with lifecycle hooks (the original plan) | Agent source unavailable locally, so hook payloads cannot be verified. `AGENTS.md` rule 1 forbids designing against unverified shapes. Revisit if the Agent plugin API gets documented. |
| Fork `hermes-webui` to add hooks | ADR 0001 rules out a long-lived WebUI fork. |
| Per-session SSE subscriptions instead of polling | Requires knowing which sessions to watch, which needs polling `/api/sessions` anyway; adds N long-lived connections for no gain in v1. Reconsider if a global stream appears upstream. |
| Local notifications only (status quo) | Cannot fire while the app is suspended. This is exactly P0-2. |

## Owner setup checklist

Nothing here is doable from this repo — it needs the Apple Developer portal and the
server host.

1. **Apple Developer portal** — enable **Push Notifications** on App ID `app.kanso`, then
   create an **APNs Auth Key (.p8)** and record its Key ID and your Team ID
   (`H55GUGZRDX`). Download the `.p8` once; it cannot be re-downloaded.
2. **Decide where the bridge runs** — same host as `hermes-webui` is simplest; it needs
   network access to the WebUI and outbound TLS to APNs.
3. **Create the `hermes-mobile-bridge` repo** (private is fine and probably wiser).
4. **Provide the bridge a WebUI credential** — it authenticates like any client via
   `POST /api/auth/login`. Consider a dedicated credential rather than reusing yours.
5. **Expose the pairing endpoint** behind the reverse proxy on a dedicated path or
   hostname, TLS only.

Once 1 and 2 are settled, the app-side entitlement work and the bridge skeleton can both
proceed.

## Open questions

- Poll interval versus battery and server load. 30 s is a starting guess, not a measured
  choice.
- Whether cron delivery failures (`last_delivery_error`) warrant a separate notification
  kind from run completion.
- Whether to notify on `recentlyActive` transitions at all, given the app cannot
  distinguish success from failure — a "finished" push for a crashed run may be worse
  than silence.
