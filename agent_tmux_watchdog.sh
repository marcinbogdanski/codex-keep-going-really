#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || -z "${1}" ]]; then
  printf 'usage: %s SESSION_NAME\n' "$0" >&2
  exit 1
fi

SESSION_NAME="$1"
LOG_FILE="$HOME/.codex/watchdog_${SESSION_NAME//\//_}.log"
SLEEP_SECONDS=6
IDLE_SECONDS=60
NUDGE_COOLDOWN_SECONDS=60
CONTINUE_TEXT="Continue autonomously from the current state and follow the active experiment protocol in program_agenthub.md. This is an ongoing experiment loop, not a completed turn. Read the latest result, take the next action, and keep running experiments. Do not summarize or stop unless explicitly told to stop or you hit a real blocker."
last_nudge_ts="$(date +%s)"

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

  now="$(date +%s)"
  idle_for="$((now - last_activity))"
  log "state session=$SESSION_NAME pane_dead=$pane_dead current_command=$current_command idle_for=${idle_for}s since_last_nudge=$((now - last_nudge_ts))s"

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
