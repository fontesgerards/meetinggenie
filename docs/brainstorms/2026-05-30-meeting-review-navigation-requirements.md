---
date: 2026-05-30
topic: meeting-review-navigation
---

# Meeting Review Navigation — Requirements

## Summary

Add prev/next **‹ ›** arrows to the notch peek that page through your nearby meetings in time order — recent ones (read-only, showing raised vs. missed) and upcoming ones (correctable) — so you can confirm you covered everything *and* verify the AI wrote the right notes before a meeting starts. Summoned when idle from a new "Review meetings…" menu-bar item or by hovering the notch. It extends the existing glance surface; it is not a calendar or a management app.

## Problem Frame

The product retains every dismissed/expired entry in an archive (times, points, and raised/missed state), but there is no way to *see* it — the only review path today is reading `store.json`, and the menu only offers "Re-open last meeting's points." Two real moments go unserved:

- **Looking back:** right after (or some time after) a meeting, "did I actually cover everything?" — which points were raised vs. missed.
- **Looking ahead (the sharper one):** entries are written by AI agents, so before a meeting you want to *verify the AI wrote the right notes* and fix them if not. This is a trust surface for agent-authored content — it closes the loop on the AI-native capture model.

A calendar was the user's first instinct, but the product's entries are sparse (a few agent-written meetings, manually timed), and a calendar grid collides with the explicit "no full management GUI / glance surface, not a document" identity. Paging through nearby meetings with arrows delivers both review moments without a new heavyweight surface.

## Key Decisions

- **Arrows, not a calendar.** Prev/next navigation on the existing peek replaces the calendar idea — sparse entries don't need a grid, and it keeps the surface a glance tool rather than the management GUI the product rejects.
- **One time-ordered sequence: recent ← now → upcoming.** The arrows page across a single chronological run of nearby entries — recent archived entries on the ‹ side, queued upcoming entries on the › side, the active meeting (if any) in the middle.
- **Browse actions split by recency.** Past (archived) entries are **read-only** (history shouldn't change; shows raised ✓ / missed ○). Upcoming (queued) entries are **correctable** — quick-add and remove a point to fix the AI's notes — but not checkable (the meeting hasn't happened). The currently-active meeting keeps **full actions** (check-off, quick-add, remove, dismiss) as today.
- **Two ways in when idle.** A new "Review meetings…" item in the menu-bar menu opens the peek in browse mode at the nearest entry, AND hovering the idle notch reveals it. (See the idle-notch decision below.)
- **Non-interrupting when a meeting goes live mid-browse.** If a meeting's start time fires while you're browsing, the peek is never yanked; a subtle "now" indicator appears on the › side and you page to it when ready. Latest-wins (R11) is suspended for the duration of the browse.
- **Corrections also flow through the agent.** Inline quick-add/remove on an upcoming entry is a convenience; telling your agent to fix a note remains a first-class path, consistent with the AI-native model.

## Actors

- A1. **User** — pages through meetings to verify upcoming notes and confirm past coverage; occasionally corrects an upcoming entry inline.
- A2. **Agent** — writes/edits entries via the CLI (unchanged); the user reviews that output through this feature.
- A3. **Notch app** — renders the browse navigation, sources entries from the active set + archive, and enforces the per-recency action rules.

## Key Flows

- F1. **Verify an upcoming meeting's AI-written notes**
  - **Trigger:** User wants to check what the agent queued for a later meeting.
  - **Actors:** A1, A3
  - **Steps:** Open browse (menu-bar "Review meetings…" or hover the notch) → press **›** to page forward to the upcoming entry → read its points. If a point is wrong, quick-add/remove to correct it (or tell the agent).
  - **Outcome:** The user trusts (or has fixed) the points before the meeting.
  - **Covered by:** R1, R2, R3, R5, R6, R8, R10

- F2. **Confirm coverage of a recent meeting**
  - **Trigger:** After a call, "did I raise everything?"
  - **Actors:** A1, A3
  - **Steps:** Open browse → press **‹** to page back to the recent (archived) entry → read which points show raised ✓ vs. missed ○. Read-only.
  - **Outcome:** The user sees what was and wasn't raised; follow-up (if any) is theirs/their agent's to act on.
  - **Covered by:** R1, R2, R4, R7, R8

- F3. **A meeting goes live while browsing**
  - **Trigger:** A queued entry's start time arrives during a browse.
  - **Actors:** A3, A1
  - **Steps:** The peek stays on the entry being viewed; a "now" indicator appears on the › side. The user finishes glancing, then pages › to the live meeting (or dismisses, which surfaces the live meeting).
  - **Outcome:** Review is never interrupted; the live meeting is one glance away and is surfaced on exit.
  - **Covered by:** R9, R11, R12

## Requirements

**Navigation**

- R1. The peek shows prev (**‹**) and next (**›**) controls that page through a single time-ordered sequence of nearby entries: recent archived entries, the active entry (if any), and upcoming queued entries.
- R2. Each browsed entry displays its start time (`h:mma`) and its points, with a clear indication of whether the entry is past, now, or upcoming.
- R3. Reaching the ends of the sequence is handled gracefully (the corresponding arrow is disabled/absent at the first/last entry).
- R4. Archived (past) entries display each point's raised ✓ / missed ○ state from when the meeting was dismissed.

**Browse actions (split by recency)**

- R5. Upcoming (queued) entries are correctable while browsing: the user can quick-add a point and remove a point (subject to the existing caps), to fix agent-written notes. They are **not** checkable.
- R6. Corrections to upcoming entries persist to the same store the agent writes, so an agent and the user see one consistent entry.
- R7. Past (archived) entries are **read-only** — no check-off, quick-add, remove, or re-ordering. (Re-opening a past entry to make it live remains the existing separate "Re-open" action.)
- R8. The currently-active meeting retains its full actions (check-off, quick-add, remove, dismiss) unchanged.

**Invocation & lifecycle**

- R9. When no meeting is active, browse can be opened two ways: a "Review meetings…" item in the menu-bar menu, and hovering the notch. Both open the peek in browse mode at the nearest entry.
- R10. Hovering the idle notch reveals the browser; a plain click on the idle notch remains a no-op (refines the prior idle-notch decision — see Dependencies).
- R11. While browsing, an arriving meeting's start time does not replace or archive the browsed entry (latest-wins is suspended); instead a non-interrupting "now" indicator appears on the › side.
- R12. On exiting browse (dismiss), if a meeting went live during the browse, that now-active meeting is surfaced.

## Acceptance Examples

- AE1. **Covers R1, R5.** **Given** a queued 3:00pm entry with an incorrect point, **when** the user pages **›** to it and removes the point and quick-adds the correct one, **then** the entry's points update and persist, and no check-off control is offered.
- AE2. **Covers R4, R7.** **Given** an archived 1:00pm entry where 2 of 3 points were raised, **when** the user pages **‹** to it, **then** it shows 2 raised ✓ / 1 missed ○ and offers no edit or check-off controls.
- AE3. **Covers R9, R10.** **Given** no active meeting, **when** the user hovers the notch (or picks "Review meetings…"), **then** the peek opens in browse mode at the nearest entry; **and** a plain click on the idle notch (no hover) does nothing.
- AE4. **Covers R11, R12.** **Given** the user is browsing a past entry, **when** a 2:00pm meeting's start time arrives, **then** the view stays on the browsed entry and a "now" indicator appears on the › side; **when** the user then dismisses, **then** the 2:00pm meeting is surfaced as the active peek.
- AE5. **Covers R3.** **Given** the user is on the earliest archived entry, **when** they look at the **‹** control, **then** it is disabled/absent.

## Scope Boundaries

### Deferred for later
- **Agent-facing programmatic archive read-back** (the originally-deferred CLI/skill "raised vs. missed" summary / follow-up drafting). This feature is the *user-facing visual* half; the agent-facing half stays deferred unless explicitly folded in. Both read the same archive.
- A **jump-to-date / search** affordance over a long archive (paging only, for now).

### Outside this product's identity
- A **calendar grid** or dense multi-day overview (rejected: sparse entries; collides with "glance, not document").
- A **full management GUI** for entries. Editing is limited to correcting *upcoming* entries inline; agent-driven correction remains primary. Past entries are never editable.
- Anything that reads external sources (calendars, platforms) to populate the timeline — the sequence is built only from the local store's entries + archive.

## Dependencies / Assumptions

- **Refines the idle-notch decision.** The shipped product made the idle notch inert (a click is a no-op, to resolve the re-open/R13 conflict) and invisible when idle (R23). This feature adds a **hover** reveal for browse; the click-is-a-no-op rule is preserved (hover ≠ click). Planning should reconcile R10 here with the existing R13/R23 behavior.
- **Builds on retained archive (origin R15).** No new persistence of meeting data is required — the archive already holds past entries with checked state; upcoming entries already exist in the active set.
- **Reuses existing edit paths.** Upcoming-entry correction reuses the existing quick-add/remove (entry-by-id) operations and caps; no new edit verbs.
- Assumes the nearby-entry sequence is bounded to a sensible recent/upcoming window rather than the entire archive (see Outstanding Questions).

## Outstanding Questions

### Deferred to planning
- **Sequence bounds:** how far back into the archive and forward into the queue the arrows traverse (e.g., a recent rolling window + all upcoming, vs. everything). Default toward a bounded recent window to avoid endless paging.
- **Hover-reveal mechanics:** hit region, reveal delay, and whether the browser dismisses on mouse-away vs. requires the × — and how this coexists with the screen-capture-exclusion and non-activating-panel behavior.
- **"Now" indicator specifics:** its exact affordance, and whether it also applies when browse was summoned while idle.
- **Empty states:** what browse shows when there are no past entries (or no upcoming entries) to page to.
- Whether to surface the agent-facing read-back (deferred) at the same time, since it shares the archive data.
