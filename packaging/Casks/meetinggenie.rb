# Source of truth for the Homebrew cask (plan U5). Copied to the tap repo
# github.com/fontesgerards/homebrew-meetinggenie-tap under Casks/meetinggenie.rb.
# Install: brew install --cask fontesgerards/meetinggenie-tap/meetinggenie
#
# Fill `version` + `sha256` from scripts/make-dmg.sh output each release (the
# release runbook owns the bump). No livecheck for v1 (core-tap convention,
# deferred). `auto_updates true` tells Homebrew the app self-updates via Sparkle
# so bare `brew upgrade` leaves it alone.
cask "meetinggenie" do
  version "0.1.0"
  sha256 "FILL_FROM_make-dmg.sh"

  url "https://fontesgerards.github.io/meetinggenie/MeetingGenie-#{version}.dmg"
  name "MeetingGenie"
  desc "Privacy-first macOS notch app for meeting talking points; ships the notch CLI"
  homepage "https://fontesgerards.github.io/meetinggenie/"

  auto_updates true
  depends_on macos: ">= :ventura"

  app "MeetingGenie.app"
  # Put the bundled CLI on PATH (the VS Code `code` pattern).
  binary "#{appdir}/MeetingGenie.app/Contents/Resources/notch"

  # Minimal cleanup — only the local store + prefs the app writes.
  zap trash: [
    "~/Library/Application Support/MeetingGenie",
    "~/Library/Preferences/com.fontesgerards.meetinggenie.plist",
    "~/Library/Saved Application State/com.fontesgerards.meetinggenie.savedState",
  ]
end
