# ADR 0001 — Fork and upstream strategy

- **Status:** Accepted, **partially superseded 2026-08-30**

> **Superseded:** sections 1 ("fork and harden, do not rewrite") and 6 (defer the rename)
> no longer describe the project. On 2026-08-30 the owner renamed the project, scheme,
> targets and directories to `Kanso*` and accepted that upstream merging is no longer
> practical. The source was **kept** — this was a rename, not a rewrite, so section 1's
> reasoning about not discarding tested behaviour still stands and was honoured. What
> changed is that upstream is no longer a merge source: PR #33 (the unfixed half of #291)
> and the staged voice series #248–257 must now be reimplemented by hand rather than
> pulled. Cherry-picking individual upstream fixes remains possible but manual.
> Everything else in this ADR — the three repository boundaries, `master` as the
> integration branch, the layer-attribution rule, public visibility and its discipline —
> is unchanged.
- **Date:** 2026-08-27
- **Deciders:** Repository owner
- **Supersedes:** nothing

## Context

Kanso is a fork of [Hermex](https://github.com/uzairansaruzi/hermex) (MIT), a native
SwiftUI iPhone client for a self-hosted Hermes agent stack. At the time of this decision
`master` is byte-identical to upstream `master` at `b4f26bf` — the fork has zero
divergence.

Upstream is active (1100+ stars, ~25 open issues) and moves quickly. Several defects the
fork cares about are already filed upstream, including long-stream unresponsiveness
(#291), stale background Live Activity completion (#290), generated titles leaking into
the transcript (#288), and Kanban resetting the browsed board (#259). A staged voice
programme (#248–#257) is also in flight upstream.

The fork needs private product features — a Home/Work information architecture, remote
push, and durable notification delivery — that upstream may not want. It also needs the
upstream bug fixes. Those two needs pull in opposite directions.

Three consumers are involved, each with a different change velocity and ownership:

1. the iOS app (this repository);
2. `hermes-webui`, the server API surface — upstream, community-owned;
3. Hermes Agent itself, which owns cron, Kanban, and tool execution.

## Decision

### 1. Fork and harden. Do not rewrite.

The upstream app is substantial: 193 Swift sources, 95 test files, existing SSE stream
lifecycle handling, replay sequencing, snapshot reconciliation, approval and clarification
overlays, Live Activities, a Share Extension, cron CRUD, and broad Kanban support. A
rewrite would discard tested behavior and reintroduce solved correctness problems.

### 2. Three repository boundaries

| Boundary | Owner | Contains |
|---|---|---|
| iOS app fork (this repo) | Owner | Product and native experience |
| `hermes-mobile-bridge` (future) | Owner | Standalone, versioned Hermes plugin plus service for device pairing, events, push |
| `hermes-webui` | Upstream community | Consumed as-is; general fixes contributed back |

**No long-lived `hermes-webui` fork.** Private mobile functionality goes in the
standalone bridge, not scattered through WebUI endpoints.

### 3. Remote and branch layout

```
origin    → https://github.com/KasparWe/kanso        (fetch + push)
upstream  → https://github.com/uzairansaruzi/hermex  (fetch only; push URL disabled)
```

The `upstream` push URL is deliberately set to an invalid value so an accidental
`git push upstream` fails loudly instead of attempting to write to someone else's
repository.

**`master` remains the integration branch.** The source plan proposed `main`; renaming
would break CI, branch protection, and upstream comparison for no product gain. This is a
knowing deviation from the plan.

Branch naming follows `AGENTS.md`: `issue/<n>-slug` for issue-backed work,
`chore/` or `fix/` for work with no issue. One issue → one short branch → one PR.

### 4. Where a fix belongs

Diagnose the layer before writing code. A mobile symptom can originate in Swift, WebUI,
Hermes Agent, the reverse proxy, or the model provider.

- **App-layer defect** → fix in this fork.
- **General WebUI or Hermes defect** → contribute upstream. If the fork cannot wait,
  isolate the workaround, comment it with the upstream issue link, and remove it when
  upstream lands the fix.
- **Private product behavior** → this fork, or the standalone bridge.

### 5. Upstream sync cadence

`UPSTREAM_TESTED_SHA` and `UPSTREAM_TRIAGED_SHA` pin the validated WebUI commits and
stay authoritative. The existing `upstream-watch.yml` workflow produces a weekly drift
digest. Merge upstream deliberately — after a digest and a green suite — never
opportunistically mid-slice.

### 6. Identity and branding — SUPERSEDED 2026-08-30

**Original decision (no longer in force):** the Xcode scheme, targets, bundle identifiers
and source symbols would keep upstream's `Hermex`/`HermesMobile` naming, with a code-wide
rename deferred to Phase 5, because renaming would touch nearly every file and destroy
mergeability with upstream precisely during Phase 1 — when the fork depended most on
pulling upstream fixes.

**What actually happened:** the owner reversed this on 2026-08-30, after Phase 1's five
P0 entries were resolved and Phase 2's app-side work had landed. The project, scheme, all
four targets and all four source directories were renamed to `Kanso*`, and the loss of
practical upstream merging was accepted explicitly. The cost the original decision
predicted was real but had shrunk: the Phase 1 work that most needed upstream was already
done.

The rename cost far less than feared — because file references are group-relative,
rewriting four group `path` entries carried all 1172 `.swift` references automatically.

Identity now lives in `Config/Shared.xcconfig` and belongs to the fork:
`app.kanso` / `group.app.kanso`. Per-machine signing overrides still go in a gitignored
`Config/Local.xcconfig`, per `CONTRIBUTING.md`; `project.pbxproj` is still never edited
for signing.

### 7. Repository visibility

The fork stays **public**. This preserves the GitHub fork relationship, the upstream
compare view, and frictionless upstream pull requests, and the code is MIT and already
public upstream.

The consequence is binding: **nothing owner-specific may be committed.** No server
hostnames, no credentials, no tokens, no APNs keys, no transcript content, no personal
data. Machine- and deployment-specific state lives only in the gitignored `CURRENT.md`
and `Config/Local.xcconfig`.

## Consequences

**Positive**

- Tested upstream behavior is retained rather than reimplemented.
- Upstream fixes remain mergeable because divergence stays small and deliberate.
- Server-side private functionality is versioned separately and can be installed,
  upgraded, or removed without touching WebUI.
- A future hosted push relay can be added at the bridge boundary without rewriting app
  navigation.

**Negative**

- Two-repository diagnosis costs time: every defect needs layer attribution before a fix.
- Upstream may reject a contributed fix, forcing a documented local patch.
- Public visibility exposes product strategy and requires permanent discipline about
  what is committed.
- Deferring the rename means the codebase says "Hermex" while the product is called
  "Kanso" — a standing source of confusion until Phase 5.

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| Rewrite the app natively from scratch | Discards ~95 test files of solved streaming and reconciliation correctness |
| Permanent `hermes-webui` fork | Every upstream server change becomes a merge conflict; private endpoints leak into a community surface |
| Hard-detach (no fork relationship, upstream as a plain remote) | Loses the compare view and easy upstream PRs; only justified if the repo must be private |
| Rename everything to Kanso now | Touches nearly every file and breaks upstream mergeability during the phase that needs it most |
| Make the fork private | GitHub cannot privatize a fork; would need a fresh repo, losing the upstream relationship |

## Follow-ups

- ADR 0002 — Mobile Bridge architecture, before any bridge implementation. Must confirm
  the exact Hermes hook payloads and where plugins load in both WebUI-originated and
  gateway/cron processes. Do not assume.
- Enable Issues and Actions on the fork so work tracking and CI both function.
