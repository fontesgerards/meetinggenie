# MeetingGenie — Design System

A privacy-first macOS **notch utility**. During a meeting it drops a small "peek"
of your prepared talking points down out of the MacBook notch — a calm,
always-on-top, never-interrupting glance surface that a fullscreen Zoom/Meet
call can't bury. Points are written primarily by **AI agents** through a local
`notch` CLI; the only data ever stored is times and note text. No calendar, no
integrations, no account, local-only.

> "The macOS notch is the one region the system keeps above everything,
> including fullscreen calls. That makes it the natural home for *things to
> bring up right now*."

This repository is the **design system** for MeetingGenie: its foundations
(color, type, geometry, motion), its content/voice rules, its iconography, and a
high-fidelity **UI kit** that recreates the notch peek and its states so you can
design new surfaces, marketing, or features that look and feel native to the
product.

---

## Sources

Everything here was derived by reading the product's own source. If you have
access, explore these to go deeper — the Swift implementation is the ground
truth for every measurement in this system.

- **GitHub — product (primary source):** `fontesgerards/meetinggenie` (private)
  Key files read to build this system:
  - `docs/design-brief.md` — the visual brief (look & feel baseline)
  - `docs/brainstorms/2026-05-29-notch-meeting-reminders-requirements.md` — vision, voice, constraints
  - `Sources/MeetingGenieApp/PeekView.swift` — colors, opacities, type sizes, layout
  - `Sources/MeetingGenieApp/NotchShape.swift` — the notch & "T" silhouette geometry
  - `Sources/MeetingGenieApp/NotchGeometry.swift` — placement / notch detection
  - `Sources/MeetingGenieApp/PeekController.swift` — peek lifecycle, row/spacing metrics
  - `Sources/MeetingGenieApp/AppDelegate.swift` — menu-bar item & menu
  - `Sources/notch/main.swift` — the agent-facing CLI (voice of the CLI)
  - `Sources/NotchCore/{Entry,Validation,TimeFormatting}.swift` — data model & limits
- **GitHub — also attached:** `fontesgerards/friendmaptap` (private). Not part
  of MeetingGenie; appears to be a separate product ("MapTap for friends") and
  was **not** used in this system. Flagged here so the reader knows it was seen.

> You can explore the repositories above to build richer, more accurate designs
> against this product than this snapshot captures.

---

## What this is NOT

MeetingGenie is **deliberately bare**. There is no logo lockup, no brand
typeface, no color palette beyond black/white/green, and no marketing site in
the source. The design brief explicitly leaves typography hierarchy, spacing
rhythm, micro-interactions, motion, and elevation **open for design**. This
system therefore does two jobs:

1. **Document** the precise, real values already in the product (exact radii,
   opacities, paddings, type sizes — all lifted from Swift).
2. **Propose** the thin layer of structure the product was left open for
   (a motion spec, a spacing rhythm, hover/press states) — clearly marked as
   *proposed* where it extends beyond what ships today.

Stay inside the constraints (below) and you cannot go wrong.

### Hard constraints (never violate)

- **Black-on-notch, flush to the top.** The surface is `#000000` so it reads as
  the hardware notch growing downward. No border, no drop shadow on the panel.
- **The menu-bar band stays notch-width only** (the "T" shape) so the peek never
  covers menu-bar items that flank the notch.
- **Never steals keyboard focus.** Quick-add only takes focus on a deliberate
  activation. It is an ambient surface, not a window.
- **Privacy-first, local-only, agent-written.** Only times + note text exist.
  Never depict calendars, attendees, meeting titles, or platform logos.
- **A glance surface, not a document.** Type tops out at caption sizes; lists
  are capped (≤7 points, ≤80 chars each). If it feels dense, it's wrong.

---

## CONTENT FUNDAMENTALS

The product has two distinct voices: the **surface voice** (what the user sees
on the notch) and the **CLI/agent voice** (how agents drive it). The
documentation voice (this repo, the README, the requirements) is a third.

### The surface voice — terse, ambient, lowercase-time

The peek shows almost no chrome words. The only fixed copy is:

- The **time label** rendered as `1:51pm` — **lowercase, no space**, `h:mma`
  format (e.g. `2:00pm`, `11:30am`). This is a hard format from
  `TimeFormatting.swift`; never write "2:00 PM" or "14:00".
- The **"Add point"** affordance label (sentence case, two words).
- The quick-add field placeholder: **"Add a point…"** (note the ellipsis
  character `…`, sentence case).
- The dismiss control's tooltip: **"Done — archive these points"** (em dash).

Point text itself is **user/agent-authored** and is treated as inert, untrusted
data — never a place for product voice. It tends to be **imperative fragments**:
*"raise the budget question"*, *"ask about Q3 timeline"*, *"mention the new
hire"*. Lowercase, no terminal punctuation, verb-first, ≤80 characters.

### The CLI/agent voice — calm, factual, no exclamation

The CLI confirms actions in flat, lowercase, present/past statements:

- `added entry at 2:00pm with 2 point(s)`
- `added point to entry at 2:00pm`
- `removed point 1 from entry at 2:00pm`
- `cleared active entries`
- `(no active entries)` — parenthetical for empty states.

Errors are prefixed `notch:` and are blunt and specific:
`notch: could not parse time '2 oclock'`,
`notch: an entry may hold at most 7 points`. No apologies, no emoji, no
"oops". The CLI usage block uses `<time>`, `<point>...`, `<n>` placeholder
conventions.

### The documentation voice — precise, decision-led, honest about limits

The requirements and brief are written in **clear declarative prose** with an
unusual amount of intellectual honesty: decisions are named ("**Latest-wins on
collision.**"), trade-offs are stated out loud ("an accepted privacy
trade-off"), and unverified things are flagged ("the GUI compiles and links,
but its runtime behavior cannot be verified"). Requirements are numbered
(`R1`, `R12`), flows are labelled (`F1`–`F4`), acceptance examples use
**Given / when / then**.

### Casing, person, punctuation, emoji

- **Casing:** Sentence case for UI labels; lowercase for times and point text;
  Title Case only for the product name **MeetingGenie** (one word, two caps).
- **Person:** Second person and possessive in docs/marketing ("**your** prepared
  points", "you glance at and check off"). The surface itself addresses no one.
- **Punctuation:** Em dashes for asides; the real ellipsis `…`; `(n)` /
  `point(s)` plural hedging in CLI output.
- **Emoji:** Effectively none in the product surface or CLI. The README uses a
  single `⚠️` to flag verification status — treat emoji as a doc-only accent,
  **never** in the peek or marketing UI.
- **The vibe:** *Quiet competence.* Nothing shouts. The product's whole pitch is
  that it doesn't interrupt — the copy mirrors that: short, unhurried, certain.

---

## VISUAL FOUNDATIONS

### Color

A **monochrome-plus-one** system. There is no grey ramp — hierarchy is expressed
entirely through **white at graded opacity** over true black, with a single
green reserved for the "done" state.

- **Surface:** `#000000` true black (`Color.black`). It must be true black so it
  is indistinguishable from the physical notch. The panel has **no border and no
  shadow** — elevation is implied by the notch itself, not by chrome.
- **Text/icon opacity ladder:** primary `1.0` (live point text) → secondary
  `0.55` (time label, "Add point") → idle icon `0.50` (hollow circle, ×) →
  done text `0.45` → strikethrough rule `0.40`. Memorize this ladder; it is the
  entire neutral system.
- **Accent:** Apple **systemGreen**, dark variant `#30D158` (`Color.green`).
  Used **only** for the checked checkmark fill. Green means "I raised it."
  Nothing else is ever colored — no blue links, no red destructive, no warning
  amber on the surface.

### Type

The macOS **system font (SF Pro)** exclusively, via the native system stack —
this renders as SF Pro on Apple devices, which is the authentic look. The peek
lives in **caption / caption2** sizes (≈12px / ≈11px): it is a glance surface,
not a reading surface, so the scale tops out small on purpose. Point text leans
**medium (500)** for legibility against black; the time label and "Add point"
are regular weight at reduced opacity. CLI/store contexts use **SF Mono**.

### Geometry — the notch silhouette (most brand-defining element)

The shape is the brand. Two silhouettes, both with a black fill that reads as
the notch extending downward:

- **`NotchTShape` (notched displays):** within the menu-bar band the painted
  width is only the **physical notch width** (~240pt, centered in the empty
  menu-bar gap so it never covers menu items). Below the band it **flares
  outward through concave shoulders** (radius **12pt**) into the full **~360pt**
  body, which has **convex bottom corners** (radius **20pt**). Square top edge
  (it sits over the physical notch).
- **`NotchShape` (non-notch fallback):** a rounded rect with **concave top
  corners** (radius **11pt**) and **convex bottom corners** (**20pt**).

The concavity is the signature: top corners curve *outward into the screen
edge*, bottom corners round *inward* — so the panel looks grown from hardware,
not pasted on. Quick-add field corners are a gentle **6pt**.

### Spacing rhythm

Built on a **6 / 8 / 14 / 18** step. Horizontal padding **18pt**; **8pt** gap
below the notch band before content; **14pt** bottom padding; **6pt** between
point rows and between a row's icon and text; **8pt** between the list column
and the × control. Rows are a fixed **26pt** tall (used to compute panel height:
`band + rows×26 + 76` chrome). Lists are capped at **7 points**.

### Backgrounds, texture, imagery

None. The surface is **flat true black** — no gradients, no texture, no grain,
no imagery, no blur/material. (The product is excluded from screen capture, so
it never even appears in a recording.) This austerity is intentional and is the
opposite of typical "AI app" visual tropes. Any marketing imagery built around
the product should photograph a **real Mac with the peek on the notch** rather
than invent decorative backgrounds.

### Motion *(proposed — none ships today)*

The app currently animates **nothing** ("currently instant — no motion design
exists yet"). The design-system recommendation, consistent with an ambient
surface: **calm ease-out, quick, never bouncy.**

- **Show / dismiss:** the panel slides + fades down from behind the notch over
  **~220ms** with `cubic-bezier(0.32, 0.72, 0, 1)` (a soft decelerate). It
  should feel like it was always there, not like it popped.
- **Check-off:** ~140ms — the circle fills green and the text dims + strikes
  through together. A tiny scale-punch (1.0→1.08→1.0) on the checkmark is the
  *one* permissible flourish.
- **Quick-add reveal:** the + row crossfades to the field over ~220ms.
- Nothing overshoots or springs. Respect `prefers-reduced-motion` by snapping.

### Hover / press states *(proposed)*

- **Hover:** raise the element's opacity one rung (e.g. a `0.50` icon → `0.75`).
  No background highlight on the black surface.
- **Press:** drop to `0.9` scale and/or full white briefly. The check-off is the
  primary press target — it should feel tactile but quiet.

### Cards, borders, shadows, elevation

- **The peek panel:** no border, no shadow, no card. It *is* the surface.
- **Inset elements (quick-add field):** a faint `rgba(255,255,255,0.08)` fill
  and a `0.10` hairline border at **6pt** radius — the only "card-like" element
  in the product. No inner shadow.
- **Dividers:** if ever needed, a single `rgba(255,255,255,0.10)` hairline.
  Used sparingly — the spacing rhythm usually carries separation alone.

### Layout rules

- The peek is **fixed** to top-center of the notch display, flush to the
  physical top edge (frame snapped to pixel boundaries, bleeds 1pt above to
  avoid a hairline seam). It is **left-aligned** content with the dismiss
  control pinned **top-right**, deliberately separate from the list body.
- Width is fixed (~360pt); **height grows with point count**. Empty entries
  don't open at all (a no-op).

---

## Iconography

See the **ICONOGRAPHY** section below (kept together with the asset notes).

### ICONOGRAPHY

MeetingGenie uses **Apple SF Symbols** exclusively — it is a native macOS/SwiftUI
app, so every glyph is an `Image(systemName:)`. There is no custom icon set, no
icon font of the product's own, and no PNG icons. The exact symbols in use:

| Role | SF Symbol | Where |
|---|---|---|
| Menu-bar item | `note.text` | the status-bar icon |
| Unchecked point | `circle` | hollow circle, `0.5` white |
| Checked point | `checkmark.circle.fill` | filled, **green** |
| Add a point | `plus.circle` | the "Add point" affordance |
| Dismiss / done | `xmark.circle.fill` | filled `×`, pinned top-right, `0.5` white |

**Style characteristics:** rounded, medium-stroke outline symbols at caption
optical sizes, monochrome white-on-black (green only for the checked fill). They
are simple, geometric, and quiet — no duotone, no multicolor, no hierarchical
rendering.

**Substitution for web/HTML (flagged):** SF Symbols are Apple-proprietary and
cannot be redistributed or used outside Apple platforms. For the HTML UI kit and
preview cards this system substitutes **[Lucide](https://lucide.dev)** (loaded
from CDN), which is the closest open match — clean, geometric, rounded
stroke icons. The mapping used: `circle` → `circle`,
`checkmark.circle.fill` → `check-circle-2`/filled circle+check,
`plus.circle` → `plus-circle`, `xmark.circle.fill` → `x-circle`,
`note.text` → `notebook-pen` / `sticky-note`. **On real Apple surfaces, always
use the genuine SF Symbols above** — the Lucide versions are an approximation
for cross-platform rendering only. *If you need pixel-true icons, supply the
SF Symbols renders.*

Emoji and unicode glyphs are **not** used as icons anywhere in the product.

---

## Index — what's in this design system

Root files:

- **`README.md`** — this file. Product context, voice, visual foundations,
  iconography, and the file index.
- **`colors_and_type.css`** — all design tokens as CSS custom properties
  (color/opacity ladder, type scale, geometry/radii, spacing, motion) plus a
  few semantic helper classes (`.mg-surface`, `.mg-time`, `.mg-point`, etc.).
- **`SKILL.md`** — Agent-Skill manifest so this system can be used directly
  inside Claude Code / other agents.

Folders:

- **`assets/`** — SVG glyph references and any product marks used by the kit.
- **`fonts/`** — (none bundled — the product uses the macOS system font, SF Pro,
  which is proprietary and cannot be redistributed; the system font stack in
  `colors_and_type.css` resolves to it on Apple devices).
- **`preview/`** — small HTML specimen cards that populate the Design System tab
  (colors, type, geometry, spacing, components, brand).
- **`ui_kits/notch-peek/`** — the high-fidelity, interactive recreation of the
  notch peek and its states (`index.html` + JSX components + its own README).

> No slide template ships with the product, so no `slides/` are included.

---

## Open questions / where to push further

- **Motion** is entirely proposed here — confirm the show/dismiss feel on a real
  notched Mac before treating it as canon.
- A **non-notch fallback** surface is deferred in the product; if it's built,
  this system's geometry section will need a floating-panel variant.
- If marketing ever needs a **logo/wordmark**, none exists yet — design one
  inside these constraints (monochrome, the notch silhouette as a motif).
