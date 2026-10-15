#!/usr/bin/env bash
# claude-remote.sh — keep Claude Code Remote Control running on macOS
#
# Usage:
#   ./claude-remote.sh start   [dir]   Start in the background (inside a detached screen session)
#   ./claude-remote.sh stop            Stop it
#   ./claude-remote.sh restart [dir]   Restart
#   ./claude-remote.sh status          Show whether it is running
#   ./claude-remote.sh attach          Attach to the terminal UI (detach with Ctrl-A then D)
#   ./claude-remote.sh log             Follow the log
#   ./claude-remote.sh install [dir]   Start at login via launchd, restart if it exits
#   ./claude-remote.sh uninstall       Remove the launchd agent and stop
#
# Environment variables:
#   CLAUDE_RC_DIR         Working directory          (default: $HOME)
#   CLAUDE_RC_NAME        Session name               (default: computer name)
#   CLAUDE_RC_PERM        Permission mode            (default: unset, use your own settings;
#                                                     e.g. auto, acceptEdits, bypassPermissions)
#   CLAUDE_RC_SPAWN       same-dir | worktree | session (default: same-dir)
#   CLAUDE_RC_AUTO_TRUST  1 = answer "y" to the folder-trust prompt automatically (default: 0)

set -euo pipefail

SCREEN_NAME="claude-remote"
LABEL="com.user.claude-remote"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/claude-remote"
LOG_FILE="$LOG_DIR/claude-remote.log"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

WORK_DIR="${2:-${CLAUDE_RC_DIR:-$HOME}}"
RC_NAME="${CLAUDE_RC_NAME:-$(scutil --get ComputerName 2>/dev/null || hostname -s)}"
RC_PERM="${CLAUDE_RC_PERM:-}"
RC_SPAWN="${CLAUDE_RC_SPAWN:-same-dir}"
RC_AUTO_TRUST="${CLAUDE_RC_AUTO_TRUST:-0}"

CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
[[ -x "$CLAUDE_BIN" ]] || { echo "claude CLI not found"; exit 1; }

mkdir -p "$LOG_DIR"
# The screen 4.0 that ships with macOS has no -Logfile flag, so set the log path in a screenrc
SCREENRC="$LOG_DIR/screenrc"
printf 'logfile %s\nlogfile flush 1\nscrollback 5000\n' "$LOG_FILE" >"$SCREENRC"

is_running() {
  # `screen -ls` exits 1 on macOS even when sessions exist, so avoid piping it under pipefail
  local list; list="$(screen -ls 2>/dev/null || true)"
  grep -q "[0-9]\.${SCREEN_NAME}[[:space:]]" <<<"$list"
}

# Watch the screen for up to 60s after start. If CLAUDE_RC_AUTO_TRUST=1 and a [y/N]
# prompt (the folder-trust check) appears, answer y. Stops once it sees "Connected".
TRUST_PENDING=0
watch_startup() {
  local snap="$LOG_DIR/.screen-snap.txt"
  for _ in $(seq 1 30); do
    sleep 2
    is_running || continue
    rm -f "$snap"
    screen -S "$SCREEN_NAME" -p 0 -X hardcopy "$snap" 2>/dev/null || continue
    sleep 0.5
    [[ -f "$snap" ]] || continue
    if grep -q 'Connected' "$snap"; then break; fi
    if grep -v '^[[:space:]]*$' "$snap" | tail -n 3 | grep -q '\[y/N\][[:space:]]*$'; then
      if [[ "$RC_AUTO_TRUST" == "1" ]]; then
        screen -S "$SCREEN_NAME" -p 0 -X stuff $'\025y\r'   # Ctrl-U, y, Enter
        echo "[$(date '+%F %T')] auto-answered [y/N] prompt" >>"$LOG_FILE"
      else
        TRUST_PENDING=1
        echo "[$(date '+%F %T')] waiting on a [y/N] prompt; run 'claude' in $WORK_DIR once and trust the folder, or set CLAUDE_RC_AUTO_TRUST=1" >>"$LOG_FILE"
        break
      fi
    fi
  done
  rm -f "$snap"
}

claude_cmd() {
  # caffeinate -i keeps the Mac from idle-sleeping while Remote Control runs
  printf '%q ' /usr/bin/caffeinate -i "$CLAUDE_BIN" remote-control \
    --name "$RC_NAME" \
    --spawn "$RC_SPAWN" \
    ${RC_PERM:+--permission-mode "$RC_PERM"}
}

start() {
  if is_running; then
    echo "Already running (screen: $SCREEN_NAME). Use '$0 attach' to view it."
    return 0
  fi
  [[ -d "$WORK_DIR" ]] || { echo "Directory not found: $WORK_DIR"; exit 1; }
  cd "$WORK_DIR"
  echo "[$(date '+%F %T')] starting in $WORK_DIR" >>"$LOG_FILE"
  # screen gives Claude a pseudo-terminal; -L logs its output
  screen -dmS "$SCREEN_NAME" -c "$SCREENRC" -L bash -lc "$(claude_cmd)"
  watch_startup
  if is_running && [[ "$TRUST_PENDING" == "1" ]]; then
    echo "Started, but Claude is waiting for you to trust $WORK_DIR."
    echo "  Answer it with '$0 attach' (press y, then Ctrl-A D), or run 'claude' there once."
    echo "  To answer it automatically: CLAUDE_RC_AUTO_TRUST=1"
  elif is_running; then
    echo "Claude Remote Control is running"
    echo "  dir: $WORK_DIR   name: $RC_NAME"
    echo "  connect from claude.ai/code or the Claude mobile app"
  else
    echo "Failed to start, see the log: $LOG_FILE"
    tail -n 20 "$LOG_FILE" || true
    exit 1
  fi
}

# Used by launchd: run in the foreground (screen -D -m does not fork) so launchd can restart it
run_foreground() {
  cd "$WORK_DIR"
  echo "[$(date '+%F %T')] launchd starting in $WORK_DIR" >>"$LOG_FILE"
  watch_startup &
  exec screen -DmS "$SCREEN_NAME" -c "$SCREENRC" -L bash -lc "$(claude_cmd)"
}

stop() {
  if is_running; then
    screen -S "$SCREEN_NAME" -X quit
    echo "Stopped"
  else
    echo "Not running"
  fi
}

status() {
  if is_running; then
    echo "Running"; { screen -ls || true; } | grep "$SCREEN_NAME"
  else
    echo "Not running"
  fi
  [[ -f "$PLIST" ]] && echo "Start at login: installed" || echo "Start at login: not installed"
}

install() {
  [[ -d "$WORK_DIR" ]] || { echo "Directory not found: $WORK_DIR"; exit 1; }
  stop >/dev/null 2>&1 || true
  mkdir -p "$(dirname "$PLIST")"
  cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$SCRIPT_PATH</string>
    <string>_run</string>
    <string>$WORK_DIR</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>CLAUDE_RC_NAME</key><string>$RC_NAME</string>
    <key>CLAUDE_RC_PERM</key><string>$RC_PERM</string>
    <key>CLAUDE_RC_SPAWN</key><string>$RC_SPAWN</string>
    <key>CLAUDE_RC_AUTO_TRUST</key><string>$RC_AUTO_TRUST</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>$LOG_DIR/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/launchd.err.log</string>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "Installed: starts at login in $WORK_DIR and restarts if it exits"
  echo "  plist: $PLIST"
}

uninstall() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  stop >/dev/null 2>&1 || true
  echo "Uninstalled"
}

case "${1:-start}" in
  start)     start ;;
  stop)      stop ;;
  restart)   stop; sleep 1; start ;;
  status)    status ;;
  attach)    screen -r "$SCREEN_NAME" ;;
  log)       tail -f "$LOG_FILE" ;;
  install)   install ;;
  uninstall) uninstall ;;
  _run)      run_foreground ;;
  *) sed -n '2,21p' "$SCRIPT_PATH"; exit 1 ;;
esac
