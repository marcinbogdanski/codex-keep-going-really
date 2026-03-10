# codex_tmux

This folder contains a small watchdog for running `codex` inside a dedicated `tmux` session and nudging it when it appears to have gone idle too early.

## Why this exists

For long-running autonomous tasks, Codex can sometimes stop after a few iterations even when the task instructions clearly say to continue. A lightweight workaround is:

1. Run Codex in a dedicated `tmux` pane.
2. Poll `tmux` for the pane's recent activity.
3. If the pane has been idle for too long, send `please continue`.

This is intentionally simpler than a full supervisor. It does not try to restart Codex or rebuild state. It only nudges an existing session that appears to have become idle.

## How the watchdog decides to nudge

The script uses `tmux` format fields:

- `#{window_activity}`: Unix timestamp of the last activity in the window
- `#{pane_current_command}`: current foreground command in the pane
- `#{pane_dead}`: whether the pane process has exited

`tmux` does not appear to expose a precise `pane_activity` timestamp, so `window_activity` is the practical signal. This works best when Codex is running in a dedicated one-window/one-pane session.

## Files

- `agent_tmux_watchdog.sh`: the watchdog loop

## Basic usage

Start Codex in its own tmux session:

```bash
tmux new-session -d -s codex 'cd /path/to/repo && codex'
```

Run the watchdog in another shell:

```bash
cd /home/user/projects/agenthub/codex_tmux
./agent_tmux_watchdog.sh codex
```

Arguments:

- `SESSION_NAME` is required as the first positional argument

Defaults:

- target pane is always `window 0`, `pane 0`
- poll interval is fixed at `60` seconds
- logs are printed to stdout and appended to `~/.codex/watchdog_<session>.log`
- idle threshold is fixed at `600` seconds
- nudge cooldown is fixed at `600` seconds
- `CONTINUE_TEXT` is set near the top of the script:
  `Please continue from the current state. Do not summarize or stop; take the next action in the experiment loop.`

## Example

Watch a session named `codex_gpu1`:

```bash
./agent_tmux_watchdog.sh codex_gpu1
```

## Caveats

- This is a heuristic, not a guarantee.
- `window_activity` is a window-level signal, so keep Codex in a dedicated pane.
- A blind nudge can still be wrong if the model is thinking silently or waiting on something unusual.
- If the session exits entirely, this script logs that fact and exits. It does not relaunch Codex.

## Future extension

If you need a more precise idle signal, the next step would be using `tmux pipe-pane` to stream pane output into a logfile and key the watchdog off the logfile modification time instead of `window_activity`.
