---
name: meetinggenie-design
description: Use this skill to generate well-branded interfaces and assets for MeetingGenie, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping.
user-invocable: true
---

Read the README.md file within this skill, and explore the other available files.

If creating visual artifacts (slides, mocks, throwaway prototypes, etc), copy assets out and create static HTML files for the user to view. If working on production code, you can copy assets and read the rules here to become an expert in designing with this brand.

If the user invokes this skill without any other guidance, ask them what they want to build or design, ask some questions, and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need.

## What MeetingGenie is

A privacy-first macOS **notch utility** that drops a calm "peek" of prepared
meeting talking points down out of the MacBook notch. Black-on-notch, white
text, one green "done" accent, system font, SF Symbols. Points are written
mainly by **AI agents** via a local `notch` CLI. Deliberately minimal.

## Files in this skill

- `README.md` — full context: product, content/voice rules, visual foundations,
  iconography, and a file index. **Read this first.**
- `colors_and_type.css` — all design tokens (color/opacity ladder, type scale,
  notch geometry/radii, spacing, motion) + semantic helper classes.
- `assets/` — the notch silhouette SVGs (`notch-tshape.svg`, `notch-shape.svg`).
- `preview/` — specimen cards (colors, type, geometry, components, brand).
- `ui_kits/notch-peek/` — the interactive recreation of the peek + its states,
  with reusable JSX components (`NotchPeek`, `PointRow`, `MenuBar`, `Terminal`,
  `Icon`). Copy these to assemble new MeetingGenie surfaces.

## Non-negotiable constraints (read README for detail)

- Black surface (`#000000`), flush to the top, no border/shadow on the panel.
- Hierarchy via **white at graded opacity** (1.0 / .55 / .50 / .45 / .40);
  green `#30D158` **only** for the checked state.
- Menu-bar band stays **notch-width only** (the "T" shape) — never cover menu items.
- System font, **caption sizes** — it's a glance surface, not a document.
- Privacy-first: only times + note text. Never depict calendars, attendees,
  meeting titles, or platform logos.
- Copy: terse, lowercase times (`2:00pm`), imperative point fragments, no emoji,
  quiet competence. See README → CONTENT FUNDAMENTALS.

## Substitutions to flag to the user

- **SF Symbols** (Apple-proprietary) are substituted with **Lucide** for web.
  Use real SF Symbols on Apple surfaces.
- **SF Pro** is not bundled (proprietary); the system font stack resolves to it
  on Apple devices.
