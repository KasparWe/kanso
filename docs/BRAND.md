# Kanso — Brand & Color Identity

Proposal, not yet wired into code. `AppTheme.swift` still carries the inherited
Hermex gold (`#FFD700`) as the default header-logo color; §5 lists what changes when
this is accepted.

## 1. What the name has to carry

**簡素 (kansō)** is the wabi-sabi principle of *simplicity through elimination* — not
minimalism as decoration, but removing everything that isn't load-bearing until what
remains is plain and honest. That is exactly the product thesis: your server, your
phone, no middleman, no analytics, no marketing chrome.

The identity therefore has to hold two things at once:

- **Kanso (the surface):** calm, plain, quiet. Paper and ink, not neon.
- **Operator-grade (the job):** dense, scan-friendly, unambiguous status. You are
  watching an autonomous agent write to a machine you own; the UI must never be
  decorative at the cost of legibility.

**Design rule that follows from this:** color is *information*, never decoration.
One accent, four status hues, everything else neutral. If a color doesn't tell the
operator something, it shouldn't be on screen.

## 2. Palette

Two neutral ramps (warm, paper-and-ink), one accent, four status hues. Every pairing
below is contrast-checked against its own background.

### Neutrals — Sumi (墨, ink) / Washi (和紙, paper)

| Token | Hex | Role |
|---|---|---|
| `washi-0` | `#FFFFFF` | Light: raised card / sheet |
| `washi-50` | `#FBFAF7` | Light: elevated surface |
| `washi-100` | `#F5F3EF` | Light: app background |
| `washi-200` | `#E8E4DD` | Light: hairline, divider, inactive track |
| `ink-500` | `#6E6761` | Light: tertiary text (5.0:1) |
| `ink-600` | `#5C554F` | Light: secondary text (6.6:1) |
| `ink-900` | `#1C1917` | Light: primary text (15.8:1) |
| `sumi-950` | `#14110F` | Dark: app background |
| `sumi-900` | `#1C1917` | Dark: elevated surface |
| `sumi-800` | `#292524` | Dark: raised card / sheet |
| `sumi-700` | `#3A3532` | Dark: hairline, divider |
| `sumi-400` | `#928C85` | Dark: tertiary text (5.7:1) |
| `sumi-300` | `#A8A29B` | Dark: secondary text (7.4:1) |

The neutrals are warm (a red-shifted hue, not pure grey). This is the single most
identity-carrying choice in the palette: warm ink on warm paper reads as *made*, and
it separates Kanso instantly from the cold blue-grey of every other dev tool.

### Accent — Ai (藍, indigo)

Japanese indigo. Chosen over the inherited gold for three reasons: it is the
traditional companion to sumi ink; it is a *calm* accent rather than an alerting one;
and critically it does not collide with any status hue, so a tinted Send button can
never be misread as a warning.

| Token | Hex | Role |
|---|---|---|
| `ai-700` | `#26407F` | Light: pressed / focus ring (8.9:1) |
| `ai-600` | `#2F4E9E` | **Light: accent.** Links, tint, filled buttons — white on it is 7.8:1 |
| `ai-400` | `#7C9BE0` | **Dark: accent** (6.8:1); `sumi-950` on it is 6.8:1 |
| `ai-300` | `#9DB4E8` | Dark: pressed / focus ring (9.1:1) |

### Status

Four hues, each with a light-mode and dark-mode value. **Never** used as the accent.

| Meaning | Light | Dark | Notes |
|---|---|---|---|
| Streaming / active | `ai-600` `#2F4E9E` | `ai-400` `#7C9BE0` | Deliberately the accent — "the agent is working" is the app's normal state, not an alarm |
| Success / done | `#3F6B4A` matcha | `#86BE93` | 5.6:1 / 8.8:1 |
| Warning / needs input | `#8A5A12` kohaku | `#E0AE5A` | 5.3:1 / 9.3:1 |
| Error / stopped | `#A63A28` shu | `#EE8A76` | 5.8:1 / 7.6:1 |
| Offline / stale cache | `ink-500` `#6E6761` | `sumi-400` `#928C85` | Absence of color *is* the offline signal |

Never encode status by hue alone — pair every one with a glyph or label (SF Symbols
`circle.fill`, `checkmark`, `exclamationmark.triangle`, `xmark.octagon`).

### Header-logo presets (replacing the current six)

Keep the feature — user-chosen accent is good — but reframe the presets as a set of
traditional dye colors that all work against both `washi-100` and `sumi-950`:

`Ai` `#2F4E9E` · `Sora` (sky) `#4A7DA8` · `Seiji` (celadon) `#4E8368` ·
`Kohaku` (amber) `#B07A20` · `Shu` (vermilion) `#B34A32` · `Sumi` `#1C1917` ·
`Washi` `#F5F3EF`

`Ai` becomes the default in place of `#FFD700`. `prefersDarkForeground(for:)` already
handles the luminance flip for `Washi`, so no logic change is needed.

## 3. Typography & form

- **Type:** system SF Pro throughout, no custom face. SF Mono for session IDs, paths,
  tool output, diffs, and anything you might read character-by-character. A bought
  typeface would be the opposite of kanso.
- **Wordmark:** `Kanso`, SF Pro Text Medium, tracking +2%, sentence case. Never
  all-caps, never a tagline locked up with it.
- **Corner radius:** 10pt for controls, 16pt for cards, 28pt for sheets. One step per
  level, no mixing.
- **Hairlines over shadows.** 0.5pt `washi-200` / `sumi-700` dividers. Elevation comes
  from surface value, not blur — shadows are decoration, and decoration is clutter.
- **Density:** 8pt grid, 44pt minimum touch target. Padding may compress before type
  size does; never ship a scannable list at 11pt.

## 4. Logo prompt

The mark is an **enso** (円相) — the single ink brushstroke circle, drawn in one
motion, deliberately left open. It is the canonical visual for kanso, it reads at
16pt, it needs no color to work, and the gap in the ring does double duty as the
product idea: *the phone closes the loop on the machine you own.*

Paste this into an image model (Midjourney / DALL·E / Firefly / Nano Banana):

> A single enso — a Japanese zen brushstroke circle — as a minimal iOS app icon.
> One continuous confident sumi-ink stroke forming a ring, drawn in a single motion:
> the stroke starts thin at the lower left, swells naturally through the upper arc,
> and tapers to a dry brush at the end, leaving a deliberate 25-degree open gap at the
> lower right. Slight brush texture and a few dry-bristle streaks where the stroke
> thins; otherwise clean. The ring is a warm off-white (#F5F3EF) stroke on a solid,
> flat, near-black warm background (#14110F). No gradient, no glow, no bevel, no
> shadow, no drop shadow, no 3D, no reflection, no paper texture in the background,
> no outer border or rounded-rectangle frame, no text, no letters, no signature,
> no red seal or chop mark. Perfectly centered, generous margin, the ring occupying
> about 62% of the canvas width. Flat 2D vector-like rendering with organic brush
> edges. Square 1:1, 1024x1024.

Variants worth generating in the same run:

1. **Inverse** — `#1C1917` stroke on `#F5F3EF`, for light-mode marketing and the README.
2. **Accent** — `#7C9BE0` indigo stroke on `#14110F`, for the tinted/alternate icon.
3. **Monochrome glyph** — same enso as a pure single-color silhouette with no brush
   texture, for the tab bar, Live Activity, Share Extension, and the notification
   badge, where texture disappears below 24pt.

After generation, hand-trace to SVG before shipping: the App Store icon must be exact
flat vector at 1024×1024, and Live Activity / widget renderings need a clean
single-path version. If the gap in the generated ring closes or the stroke ends up
symmetrically even in width, regenerate — a mechanically even ring reads as a loading
spinner, not an enso.

**Wordmark lockup:** enso at cap height, one enso-width of space, then `Kanso`.
Horizontal only; do not stack.

## 5. What accepting this changes

- `Kanso/Config/AppTheme.swift` — `HeaderLogoColor.defaultHex` `#FFD700` → `#2F4E9E`,
  and the `presets` array replaced with §2's dye set. `KansoTests/AppThemeTests.swift`
  asserts on the current default and will need updating in the same commit.
- `Kanso/Resources/Assets.xcassets/AccentColor.colorset` — light `#2F4E9E`,
  dark `#7C9BE0`.
- App icon asset + `docs/assets/readme/hermex-icon.png` (still the inherited Hermex
  icon) and `README.md`'s "Kanso branding pending" alt text.
- Neutral and status tokens above are currently unmodelled — they'd want a
  `KansoColor` namespace alongside `AppTheme` before any view starts hardcoding hexes.
