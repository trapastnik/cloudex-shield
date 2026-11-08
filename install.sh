#!/bin/sh
# Cloudex Shield installer for macOS: one command, nothing to build.
#
#   curl -fsSL https://raw.githubusercontent.com/trapastnik/cloudex-shield/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/trapastnik/cloudex-shield/main/install.sh | sh -s uninstall
#
# Downloads the latest release, checks its SHA-256, puts Cloudex Shield.app into ~/Applications,
# starts it and turns on start at login. Downloaded with curl, the app carries no quarantine
# flag, so Gatekeeper lets the unnotarized build start. Uninstall removes all of that.
set -eu

REPO="trapastnik/cloudex-shield"
BASE="${CLOUDEX_BASE:-https://github.com/$REPO/releases/latest/download}"
ACTION="${1:-install}"
APPS="$HOME/Applications"
LABEL="io.github.trapastnik.cloudex-shield"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# CLOUDEX_NO_LAUNCH=1 (for testing): don't touch the running Cloudex Shield or its login agent.
stop_running() {
  [ "${CLOUDEX_NO_LAUNCH:-}" = "1" ] && return 0
  # A clean quit resumes any app Cloudex Shield had paused.
  pkill -x CloudexShield 2>/dev/null || true
  sleep 1
}

autostart_off() {
  [ "${CLOUDEX_NO_LAUNCH:-}" = "1" ] && return 0
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$AGENT"
}

autostart_on() {
  autostart_off
  mkdir -p "$(dirname "$AGENT")"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/open</string><string>-g</string><string>$APPS/Cloudex Shield.app</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>60</integer>
</dict>
</plist>
PLIST
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
}

uninstall() {
  stop_running
  autostart_off
  rm -rf "$APPS/Cloudex Shield.app"
  # Установленное из DMG лежит в /Applications.
  [ -w "/Applications/Cloudex Shield.app" ] && rm -rf "/Applications/Cloudex Shield.app"
  say "Cloudex Shield removed. Its settings are in ~/Library/Preferences/$LABEL.plist — delete it if you like."
}

install() {
  [ "$(uname -s)" = "Darwin" ] || fail "Cloudex Shield runs on macOS only."
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 13 ] || fail "Cloudex Shield needs macOS 13 or later."

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  say "Downloading Cloudex Shield…"
  for file in CloudexShield-macos.zip SHA256SUMS.txt; do
    curl -fsSL "$BASE/$file" -o "$tmp/$file"
  done
  (cd "$tmp" && grep -E "  CloudexShield-macos\.zip\$" SHA256SUMS.txt > wanted.txt \
    && [ "$(wc -l < wanted.txt)" -eq 1 ] && shasum -a 256 -c wanted.txt >/dev/null) \
    || fail "Checksum mismatch — the download is damaged or altered. Nothing was installed."

  stop_running
  mkdir -p "$APPS"
  rm -rf "$APPS/Cloudex Shield.app"
  ditto -x -k "$tmp/CloudexShield-macos.zip" "$APPS"
  say "Installed $APPS/Cloudex Shield.app."

  if [ "${CLOUDEX_NO_LAUNCH:-}" != "1" ]; then
    autostart_on
    open -g "$APPS/Cloudex Shield.app"
  fi
  say "Done. Open Cloudex Shield in the menu bar → Network guard: pick the apps to pause and the countries you allow."
}

case "$ACTION" in
  install) install ;;
  uninstall) uninstall ;;
  *) fail "Usage: install.sh [install|uninstall]" ;;
esac
