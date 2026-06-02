import Foundation

/// The single source of truth for the agent-facing skill (plan U6/U7).
///
/// `notch skill` prints `markdown()`; the static `skill/SKILL.md` checked into
/// the repo is byte-identical to it (a `selfcheck` assertion enforces this, so
/// the pre-install copy an agent reads can never document stale verbs). The
/// verb list drives both this doc and — where practical — the CLI's own usage,
/// so the documented surface tracks the binary.
public enum SkillDoc {
    /// One CLI verb: how it's invoked and a one-line purpose.
    public struct Verb {
        public let invocation: String
        public let summary: String
    }

    /// The point/title data verbs an agent uses to prepare a meeting. (`skill`,
    /// `help`, `list`, `clear` housekeeping verbs are documented in prose, not
    /// this table — these are the write surface.)
    public static let verbs: [Verb] = [
        Verb(invocation: #"notch add <time> [--title "<text>"] <point>..."#,
             summary: "Create or replace the entry at <time> with these points; optionally set its title."),
        Verb(invocation: "notch add-point <time> <text>",
             summary: "Append one point to the entry at <time>."),
        Verb(invocation: #"notch title <time> "<text>""#,
             summary: "Set or replace the entry's title (empty text clears it)."),
        Verb(invocation: "notch remove-point <time> <n>",
             summary: "Remove the nth (1-based) point from the entry at <time>."),
        Verb(invocation: "notch remove <time>",
             summary: "Remove the entry at <time> entirely."),
        Verb(invocation: "notch list",
             summary: "List the active entries and their points."),
    ]

    /// The Homebrew cask reference the bootstrap installs from. Provisional
    /// tap lives at `github.com/fontesgerards/homebrew-meetinggenie-tap`; pinned
    /// (never a bare placeholder) so an agent can't be steered to a spoofed tap.
    public static let caskRef = "fontesgerards/meetinggenie-tap/meetinggenie"

    /// The bootstrap one-liner: install MeetingGenie (which carries `notch`)
    /// only if `notch` isn't already on PATH. Idempotent, non-interactive.
    public static var bootstrapCommand: String {
        "command -v notch >/dev/null 2>&1 || brew install --cask \(caskRef)"
    }

    /// The complete SKILL.md — YAML frontmatter + body. The static
    /// `skill/SKILL.md` must equal this exactly (drift gate).
    public static func markdown() -> String {
        let verbLines = verbs.map { "| `\($0.invocation)` | \($0.summary) |" }.joined(separator: "\n")
        return """
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
        \(bootstrapCommand)
        ```

        If Homebrew itself is missing, install it from https://brew.sh first.

        ## Usage

        | Command | What it does |
        | --- | --- |
        \(verbLines)

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
        """
    }
}
