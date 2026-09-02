# Kanso — Product Definition

Kanso is a fork of [Hermex](https://github.com/uzairansaruzi/hermex), a native SwiftUI
iPhone client for a self-hosted Hermes agent stack.

`PROJECT_SPEC.md` remains the API and server-contract source of truth. This file owns
**product scope and priority** for the fork. Where the two disagree on product scope,
this file wins; where they disagree on API behavior, `PROJECT_SPEC.md` wins. Flag the
conflict rather than choosing silently.

> **Naming:** fully renamed as of 2026-08-30 — repository, project, scheme, targets,
> directories and bundle identifiers are all `Kanso`. "Hermes" now refers only to the
> server. See [ADR 0001](docs/adr/0001-fork-and-upstream-strategy.md).

## What this is

A **personal AI operating app**, not another model-chat client and not the Hermes WebUI
squeezed onto a phone.

- One place to talk to whichever model Hermes is configured to use.
- One place to see what is running, waiting, scheduled, blocked, or complete.
- A native capture surface for text, camera, photos, files, Share Sheet, and voice.
- A review and control surface for work that continues on the server after the phone locks.
- A self-hosted foundation whose mobile interaction quality is as dependable as a
  first-party Apple app.

The model and provider are secondary. The user picks an outcome or a working context;
Hermes owns tools, memory, skills, and provider access behind that interface. An advanced
model picker stays available, but the app must not feel like three provider apps stapled
to a settings screen.

## Success statement

The owner can open one app and confidently:

1. ask a question or attach a photo;
2. start work that may take minutes or hours;
3. leave the app without losing the run;
4. receive an actionable notification when input is needed or work finishes;
5. inspect the output, generated media, files, schedule, or Kanban card;
6. continue the same context without switching to another assistant, a browser
   dashboard, or a terminal.

## Principles

1. **Reliable before impressive.** A run that silently disappears is worse than a
   missing feature.
2. **Server owns execution; app owns interaction.** Never pretend the phone is keeping
   a task alive.
3. **One obvious next action per screen.** Advanced controls live behind disclosure.
4. **Attention, not administration.** Surface what needs the human; hide system noise.
5. **Provider-agnostic by default.** Show models only when the user chooses to care.
6. **Native capture and continuity.** Camera, Photos, Files, Share Sheet, Shortcuts,
   Live Activities, Reminders, and APNs should feel intentional, not bolted on.
7. **Canonical server state.** Local optimistic state is temporary and must reconcile
   against the server.
8. **Private by default.** Generic lock-screen notifications; transcript previews are
   opt-in.
9. **Graceful version skew.** Capabilities are negotiated; decoding is tolerant.
10. **Simple top-level navigation.** Not every Hermes subsystem earns a permanent tab.

## What makes it different

### Work survives the app lifecycle

A request may become a durable run, schedule, or Kanban card. One lifecycle vocabulary
is reused everywhere — Home, Chat, Runs, Schedules, Board, Live Activities, notifications:

`Preparing → Running → Waiting for you → Completed / Failed`

### Outcome-first, not model-first

The composer defaults to **Auto / current profile**. Model, provider, profile, workspace,
and reasoning level are available but do not dominate the primary UI.

Optional named working modes may later alias Hermes profiles without hard-coding vendors:
**Everyday**, **Deep Work**, **Build**, **Quick**. These are user-configurable aliases,
not new inference infrastructure.

### Native results, not transcript soup

Tool results become contextual objects:

| Result | Surface |
|---|---|
| Generated image | Image card — Save, Share, Retry, Continue editing |
| Document or file | Artifact card — Preview, Share |
| Created schedule | Schedule card — next run, Pause |
| Delegated task | Kanban card — status, Open in Work |
| Approval or clarification | Action card, kept attached to its run |
| Changed reminders | Native confirmation with a Reminders deep link |

The full tool log stays available under a disclosure. It is not the default reading
experience.

### Human work and agent work are separated

- **Apple Reminders** owns commitments the human personally intends to do.
- **Hermes Kanban** owns work assigned to agents or coordinated across agent profiles.
- Home may present a unified *view* with source badges, but every action preserves its
  source system.

No automatic two-way synchronization. It creates loops, duplicates, unclear ownership,
and conflict resolution nobody wants on a phone.

## Information architecture

Two primary destinations and one global creation action.

### Home

- Compact **Now** header, maximum three items.
- Priority order: approval/clarification → failed → blocked → active → recently
  completed → upcoming schedule.
- Recent and pinned conversations.
- Optional **For You** row for selected Apple Reminders lists (after EventKit work).
- Prominent New Chat; long-press offers New Voice Chat, Scan/Photo, Share/Import.

### Work

A segmented control that remembers its last segment:

1. **Runs** — active, waiting, failed, recently completed long-running sessions.
2. **Board** — mobile-first Kanban, status-focused.
3. **Schedules** — Hermes cron jobs and their run history.

If an approval is pending, Work opens directly to the affected run.

### Settings

Reached from the avatar, never a permanent tab. Servers, profiles/modes,
models/providers, notification privacy, voice, appearance, advanced tools, diagnostics,
compatibility. Skills, memory, files, providers, and analytics are contextual or live
here — not top-level.

## Visual direction

- Calm, native, information-dense, legible.
- System typography, SF Symbols, Dynamic Type, VoiceOver, Reduce Motion, semantic colors.
- Glass and material used sparingly: composer, compact Now cards, transient controls.
- **Never** expensive blur behind long scrolling transcripts or large Kanban lists.
- No provider brand colors in primary navigation.
- Status color is supplemental; every state also has text and an icon.
- Generated media may be visually rich; operational UI stays restrained.

## Mobile Kanban

A desktop horizontal board is not the primary phone UI.

- Default to **Status Focus**: one selected status, vertically scrolling cards.
- Statuses: Inbox/Triage, Ready, Running, Blocked, Done.
- Card summary: title, owner/profile, priority, dependency/block indicator, last activity.
- Swipe actions for safe transitions; explicit menus for destructive or ambiguous ones.
- Running is dispatcher-owned. Never imply that dragging a card into Running starts a worker.
- Detail: description, comments, dependencies, run history, worker log, retry/reassign.
- Dispatcher actions are secondary, previewable, and confirm before spend.

Preserve upstream's existing compatibility, offline, reconciliation, accessibility, and
uncertain-outcome safeguards.

## Schedules

User language is **Schedules**, not "Cron Jobs."

- Grouped: Needs Attention, Running, Upcoming, Paused.
- Show human schedule text, next run, last result, destination, notification policy.
- Create/edit starts simple: name, instruction, schedule, notification toggle. Model,
  profile, workspace, skills, delivery, and script/no-agent settings live under Advanced.
- Run Now, Pause/Resume, recent history, error acknowledgement, and output/session
  navigation are first-class.
- **Never** parse schedules locally. Validate against the live server contract.

## Voice

Two staged modes:

1. **Voice capture** — record or dictate, review transcript, send. This must be
   dependable before anything else ships.
2. **Voice conversation** — explicit full-screen mode with a state machine:
   Listening → Sending → Thinking/Using tools → Speaking → Listening.
   Interruption and barge-in come only after the basic loop is correct.

No always-listening background mode.

## Non-goals

- Not a webview wrapper.
- Not an admin dashboard for every Hermes subsystem.
- No server responsibilities move into this repo.
- No Reminders ↔ Kanban synchronization.
- No iPad, Mac, or Vision support in the phases covered by `ROADMAP.md`.

## Deferred decisions

Tracked, not blocking: public product name and icon; whether public users get remote push
via a maintainer-hosted relay; which Reminders lists appear in Home; whether Home greets
the user; whether named modes ship before public beta; iPad/Mac/Vision; anonymous
telemetry for public beta.
