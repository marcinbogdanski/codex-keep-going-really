#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="${SESSION_NAME:-codex}"
WINDOW_INDEX="${WINDOW_INDEX:-0}"
PANE_INDEX="${PANE_INDEX:-0}"
IDLE_SECONDS="${IDLE_SECONDS:-600}"
POLL_SECONDS="${POLL_SECONDS:-60}"
NUDGE_COOLDOWN_SECONDS="${NUDGE_COOLDOWN_SECONDS:-600}"
CONTINUE_TEXT="${CONTINUE_TEXT:-please continue}"
BLOCKING_PGREP_REGEX="${BLOCKING_PGREP_REGEX:-train.py}"

TARGET="${SESSION_NAME}:${WINDOW_INDEX}.${PANE_INDEX}"
last_nudge_ts=0

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

get_tmux_field() {
  local format="$1"
  tmux display-message -p -t "$TARGET" "$format"
}

while true; do
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "session '$SESSION_NAME' not found; waiting"
    sleep "$POLL_SECONDS"
    continue
  fi

  last_activity="$(get_tmux_field '#{window_activity}')"
  current_command="$(get_tmux_field '#{pane_current_command}')"
  pane_dead="$(get_tmux_field '#{pane_dead}')"

  now="$(date +%s)"
  idle_for="$((now - last_activity))"

  if [[ "$pane_dead" == "1" ]]; then
    log "pane $TARGET is dead; waiting for operator or external restart"
    sleep "$POLL_SECONDS"
    continue
  fi

  if (( idle_for < IDLE_SECONDS )); then
    sleep "$POLL_SECONDS"
    continue
  fi

  if (( now - last_nudge_ts < NUDGE_COOLDOWN_SECONDS )); then
    sleep "$POLL_SECONDS"
    continue
  fi

  if [[ -n "$BLOCKING_PGREP_REGEX" ]] && pgrep -f "$BLOCKING_PGREP_REGEX" >/dev/null 2>&1; then
    log "idle threshold reached, but '$BLOCKING_PGREP_REGEX' is still running; skipping nudge"
    sleep "$POLL_SECONDS"
    continue
  fi

  log "nudging $TARGET after ${idle_for}s idle (current command: $current_command)"
  tmux send-keys -t "$TARGET" "$CONTINUE_TEXT" Enter
  last_nudge_ts="$now"

  sleep "$POLL_SECONDS"
done
