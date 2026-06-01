# notch CLI reference

Full reference for the `notch` CLI that drives MeetingGenie. The canonical,
always-current version is emitted by the installed binary: `notch skill` (and
`notch --help` for the bare usage). This file mirrors it for at-rest reading
before the CLI is installed.

## Commands

| Command | What it does |
| --- | --- |
| `notch add <time> [--title "<text>"] <point>...` | Create or replace the entry at `<time>` with these points; optionally set its title. |
| `notch add-point <time> <text>` | Append one point to the entry at `<time>`. |
| `notch title <time> "<text>"` | Set or replace the entry's title; empty text (`""` or omitted) clears it. |
| `notch remove-point <time> <n>` | Remove the nth (1-based) point from the entry at `<time>`. |
| `notch remove <time>` | Remove the entry at `<time>` entirely. |
| `notch list` | List active entries and their points (shows the title when set). |
| `notch clear` | Remove all active entries (the retained archive is kept). |
| `notch skill` | Print the agent skill doc (SKILL.md) for this CLI. |

## Time format

`<time>` is a wall-clock time for **today**, parsed flexibly: `2:00pm`, `9am`,
`02:00pm`, `09:00am`, `14:30`. Out-of-range values (e.g. `13pm`, `24:00`) and
unparseable text are rejected with a non-zero exit.

## Limits & validation

- Up to **7 points** per entry; each point up to **80 characters** after
  sanitization; titles up to **60 characters**. Over-limit input is rejected at
  write time with a readable error.
- All text is sanitized as untrusted input (control/format/bidi-override
  scalars stripped, NFC-normalized, trimmed).

## Data model & privacy

Only the start **time**, the **note text**, and an optional short **title** are
stored, in a local JSON file at
`~/Library/Application Support/MeetingGenie/store.json` (mode `0600`). There is
no calendar, no attendees, no meeting-platform data, and no network write path.

## Examples

```sh
notch add 2:00pm --title "Q3 Planning" "Raise the budget" "Ask about Q3 timeline"
notch add-point 2:00pm "Mention the new hire"
notch title 2:00pm "Q3 Planning Sync"
notch list
notch remove-point 2:00pm 1
notch clear
```
