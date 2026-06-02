#!/usr/bin/env bash
# Ensure the `notch` CLI is available before an agent uses it.
#
# `notch` ships inside the MeetingGenie app; installing the cask puts it on
# PATH. This is idempotent and non-interactive: a no-op when `notch` already
# exists, otherwise a single Homebrew cask install from the pinned tap. The tap
# reference is fixed (never a bare placeholder) so the install can't be steered
# to a spoofed tap. Tap: github.com/fontesgerards/homebrew-meetinggenie-tap.
set -euo pipefail

if command -v notch >/dev/null 2>&1; then
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required but not installed. Install it from https://brew.sh, then re-run." >&2
  exit 1
fi

brew install --cask fontesgerards/meetinggenie-tap/meetinggenie
