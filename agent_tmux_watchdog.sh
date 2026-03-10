#!/usr/bin/env bash
set -euo pipefail

# Watch a dedicated tmux session and re-prompt pane 0.0 when it appears idle.
if [[ $# -lt 1 || -z "${1}" ]]; then
  printf 'usage: %s SESSION_NAME\n' "$0" >&2
  exit 1
fi

# This script is intentionally single-session and single-pane: one watchdog per tmux session.
SESSION_NAME="$1"
LOG_FILE="$HOME/.codex/watchdog_${SESSION_NAME//\//_}.log"
SLEEP_SECONDS=60
IDLE_SECONDS=600
NUDGE_COOLDOWN_SECONDS=600
CONTINUE_TEXT="Continue autonomously from the current state and follow the active experiment protocol in program_agenthub.md. This is an ongoing experiment loop, not a completed turn. Read the latest result, take the next action, and keep running experiments. Do not summarize or stop unless explicitly told to stop or you hit a real blocker."
last_nudge_ts="$(date +%s)"

# Keep logs in a stable per-user location so background runs can be inspected later.
mkdir -p "$HOME/.codex"

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
    sleep 0.15
  done

  sleep 0.5
  tmux send-keys -t "$target" Enter
}

while true; do
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "session '$SESSION_NAME' not found; exiting"
    exit 1
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
