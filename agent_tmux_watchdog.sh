#!/usr/bin/env bash
set -euo pipefail

# Watch a dedicated tmux session and re-prompt pane 0.0 when it appears idle.
if [[ $# -lt 1 || $# -gt 2 || -z "${1}" ]]; then
  printf 'usage: %s SESSION_NAME [CODEX_ROLLOUT_PATH]\n' "$0" >&2
  exit 1
fi

# This script is intentionally single-session and single-pane: one watchdog per tmux session.
SESSION_NAME="$1"
CODEX_ROLLOUT_PATH="${2:-}"
LOG_FILE="$HOME/.codex/watchdog_${SESSION_NAME//\//_}.log"
SLEEP_SECONDS=60
IDLE_SECONDS=600
NUDGE_COOLDOWN_SECONDS=600
CONTINUE_TEXT="Continue autonomously from the current state and follow the active experiment protocol. This is an ongoing experiment loop, not a completed turn. Read the latest result, take the next action, and keep running experiments. Do not summarize or stop unless explicitly told to stop or you hit a real blocker. If you hit a real blocker, print the token 'autoresearch_stop' converted to uppercase, preserving the underscore, on its own line exactly once. This signals the watchdog to exit."
last_nudge_ts="$(date +%s)"
last_rollout_line=""

# Keep logs in a stable per-user location so background runs can be inspected later.
mkdir -p "$HOME/.codex"

if [[ -n "$CODEX_ROLLOUT_PATH" && ! -r "$CODEX_ROLLOUT_PATH" ]]; then
  printf 'rollout path is not readable: %s\n' "$CODEX_ROLLOUT_PATH" >&2
  exit 1
fi

log() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "$LOG_FILE"
}

send_prompt_slow() {
  local target="$1"
  local text="$2"
  local i ch

  # Send the nudge character-by-character to avoid dumping a large paste into the tmux client.
  for ((i=0; i<${#text}; i++)); do
    ch="${text:i:1}"
    tmux send-keys -t "$target" -l "$ch"
    sleep 0.10
  done

  sleep 0.5
  tmux send-keys -t "$target" Enter
}

pane_contains_stop_marker() {
  local target="$1"

  tmux capture-pane -p -t "$target" 2>/dev/null | tr -d '\r\n' | grep -q 'AUTORESEARCH_STOP'
}

get_last_non_empty_line() {
  local path="$1"

  awk 'NF { line = $0 } END { print line }' "$path"
}

parse_rollout_turn_id() {
  local line="$1"

  jq -er '
    select(.type == "event_msg")
    | .payload
    | select(type == "object" and .type == "task_complete")
    | .turn_id
    | select(type == "string" and length > 0)
  ' <<<"$line"
}

while true; do
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "session '$SESSION_NAME' not found; exiting"
    exit 1
  fi

  if pane_contains_stop_marker "$SESSION_NAME:0.0"; then
    log "AUTORESEARCH_STOP detected in pane $SESSION_NAME:0.0; exiting"
    exit 0
  fi

  if [[ -n "$CODEX_ROLLOUT_PATH" && -r "$CODEX_ROLLOUT_PATH" ]]; then
    rollout_line="$(get_last_non_empty_line "$CODEX_ROLLOUT_PATH")"
    if [[ -n "$rollout_line" && "$rollout_line" != "$last_rollout_line" ]]; then
      if rollout_turn_id="$(parse_rollout_turn_id "$rollout_line")"; then
        now="$(date +%s)"
        log "rollout task_complete detected for turn_id=$rollout_turn_id; nudging $SESSION_NAME:0.0 immediately"
        send_prompt_slow "$SESSION_NAME:0.0" "$CONTINUE_TEXT"
        last_nudge_ts="$now"
        last_rollout_line="$rollout_line"
        sleep "$SLEEP_SECONDS"
        continue
      fi
    fi
  fi

  last_activity="$(tmux display-message -p -t "$SESSION_NAME:0.0" '#{window_activity}')"
  current_command="$(tmux display-message -p -t "$SESSION_NAME:0.0" '#{pane_current_command}')"
  pane_dead="$(tmux display-message -p -t "$SESSION_NAME:0.0" '#{pane_dead}')"

  # Use tmux activity time plus our own last-nudge time to decide when the next prompt is allowed.
  now="$(date +%s)"
  idle_for="$((now - last_activity))"
  since_last_nudge="$((now - last_nudge_ts))"
  idle_ttn="$((IDLE_SECONDS - idle_for))"
  cooldown_ttn="$((NUDGE_COOLDOWN_SECONDS - since_last_nudge))"
  if (( idle_ttn < 0 )); then
    idle_ttn=0
  fi
  if (( cooldown_ttn < 0 )); then
    cooldown_ttn=0
  fi
  ttn="$idle_ttn"
  if (( cooldown_ttn > ttn )); then
    ttn="$cooldown_ttn"
  fi
  log "state session=$SESSION_NAME pane_dead=$pane_dead current_command=$current_command idle_for=${idle_for}s since_last_nudge=${since_last_nudge}s ttn=${ttn}s"

  if [[ "$pane_dead" == "1" ]]; then
    log "pane $SESSION_NAME:0.0 is dead; waiting for operator or external restart"
    sleep "$SLEEP_SECONDS"
    continue
  fi

  if (( idle_for < IDLE_SECONDS )); then
    sleep "$SLEEP_SECONDS"
    continue
  fi

  if (( now - last_nudge_ts < NUDGE_COOLDOWN_SECONDS )); then
    sleep "$SLEEP_SECONDS"
    continue
  fi

  log "nudging $SESSION_NAME:0.0 after ${idle_for}s idle (current command: $current_command)"
  send_prompt_slow "$SESSION_NAME:0.0" "$CONTINUE_TEXT"
  last_nudge_ts="$now"

  sleep "$SLEEP_SECONDS"
done
