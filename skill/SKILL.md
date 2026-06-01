---
name: notch
description: >-
  Write a user's prepared meeting talking points to MeetingGenie, a
  privacy-first macOS notch app that surfaces them at the notch during a
  call. Use when the user asks you to prep, set up, draft, or jot
  talking points, reminders, or an agenda for an upcoming meeting or
  call, or to add, edit, retitle, or clear points for one. Drives the
  local `notch` CLI and installs it via Homebrew if it is missing.
---

# notch — MeetingGenie meeting talking points

MeetingGenie is a privacy-first macOS menu-bar app. At a meeting's start
time it shows the prepared talking points as a calm "peek" at the
MacBook notch, so the user can glance at what they wanted to raise. You
prepare those points for them via the `notch` CLI. Only the time, the
note text, and an optional short title are ever stored — there is no
calendar, no attendees, and no integrations.

## Setup (run once, then ignore)

`notch` ships inside the MeetingGenie app. Ensure it is installed before
using it — this is idempotent and a no-op when it's already present:

```sh
command -v notch >/dev/null 2>&1 || brew install --cask fontesgerards/tap/meetinggenie
```

If Homebrew itself is missing, install it from https://brew.sh first.

## Usage

| Command | What it does |
| --- | --- |
| `notch add <time> [--title "<text>"] <point>...` | Create or replace the entry at <time> with these points; optionally set its title. |
| `notch add-point <time> <text>` | Append one point to the entry at <time>. |
| `notch title <time> "<text>"` | Set or replace the entry's title (empty text clears it). |
| `notch remove-point <time> <n>` | Remove the nth (1-based) point from the entry at <time>. |
| `notch remove <time>` | Remove the entry at <time> entirely. |
| `notch list` | List the active entries and their points. |

- `<time>` is a wall-clock time like `2:00pm`, `9am`, or `14:30` (today).
- Quote multi-word points and titles. Each `add` replaces the entry at
  that time; re-running `add` without `--title` keeps the existing title.
- `notch list` shows what's currently set; `notch clear` removes all
  active entries (the archive is kept).

## When to use this

Use it whenever the user wants talking points waiting at the notch for a
meeting: "prep my 2pm", "remind me to raise the budget at 10am", "set the
title of my 3pm to Q3 Sync". Write concise, glanceable points — the user
reads them at a glance mid-call, not as a document.

Do **not** use it for general note-taking, calendars, or anything that
should persist beyond the day's meetings — that's outside what
MeetingGenie stores.
