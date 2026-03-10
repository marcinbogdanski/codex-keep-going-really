#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || -z "${1}" ]]; then
  printf 'usage: %s SESSION_NAME\n' "$0" >&2
  exit 1
fi

SESSION_NAME="$1"
LOG_FILE="$HOME/.codex/watchdog_${SESSION_NAME//\//_}.log"
last_nudge_ts=0

mkdir -p "$HOME/.codex"

log() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "$LOG_FILE"
}

while true; do
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "session '$SESSION_NAME' not found; exiting"
    exit 1
  fi

  last_activity="$(tmux display-message -p -t "$SESSION_NAME:0.0" '#{window_activity}')"
  current_command="$(tmux display-message -p -t "$SESSION_NAME:0.0" '#{pane_current_command}')"
  pane_dead="$(tmux display-message -p -t "$SESSION_NAME:0.0" '#{pane_dead}')"

  now="$(date +%s)"
  idle_for="$((now - last_activity))"

  if [[ "$pane_dead" == "1" ]]; then
    log "pane $SESSION_NAME:0.0 is dead; waiting for operator or external restart"
    sleep 60
    continue
  fi

  if (( idle_for < ${IDLE_SECONDS:-600} )); then
    sleep 60
    continue
  fi

  if (( now - last_nudge_ts < ${NUDGE_COOLDOWN_SECONDS:-600} )); then
    sleep 60
    continue
  fi

  if [[ -n "${BLOCKING_PGREP_REGEX:-train.py}" ]] && pgrep -f "${BLOCKING_PGREP_REGEX:-train.py}" >/dev/null 2>&1; then
    log "idle threshold reached, but '${BLOCKING_PGREP_REGEX:-train.py}' is still running; skipping nudge"
    sleep 60
    continue
  fi

  log "nudging $SESSION_NAME:0.0 after ${idle_for}s idle (current command: $current_command)"
  tmux send-keys -t "$SESSION_NAME:0.0" "${CONTINUE_TEXT:-please continue}" Enter
  last_nudge_ts="$now"

  sleep 60
done
