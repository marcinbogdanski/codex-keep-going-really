# Codex, no, really keep going, seriously

**EDIT: Looks like OpenAI hooks engine was just merged: [start of hooks engine](https://github.com/openai/codex/pull/13276). This in theory should be preferred solution to Tmux watchdog below.**

---

Two workarounds that together allow using codex for [autoresearch](https://github.com/karpathy/autoresearch).

Codex by default in unusable for autoresearch [link](https://github.com/karpathy/autoresearch/issues/57)

Combining these two workarounds I was able to wake up to 2 agents still runing overnight (after 7h, 55/53 experiments each).

## System Prompt

Codex GPT-5.4 original system prompt (see: [CODEX_GPT54_BASE_INSTRUCTIONS.md](CODEX_GPT54_BASE_INSTRUCTIONS.md), taken from codex source code repo) implies turn based nature of work.

With Codex we modified this to [CODEX_GPT54_AI_RESEARCHER.md](CODEX_GPT54_AI_RESEARCHER.md) which applies minimum changes to:

- explicitly specify ongoing infinite nature of work, and
- put emphasis on AI research work (if you're using it for something else rephrase that part)
- other than that kept most parts of the original prompt unchanged

**How to use**

```bash
git clone git@github.com:karpathy/autoresearch.git
cd autoresearch
mkdir .codex
touch .codex/config.toml
```

Then insert this line in `config.toml`

```bash
model_instructions_file = "/path/to/folder/CODEX_GPT54_AI_RESEARCHER.md"
```

Start codex as normal, to confirm it worked with this question:

```
According to your instructions, is 'git reset --hard' allowed? What execptions exist?
```

Model should list two exceptions:

- user explicitly asked for hard reset (present in both system prompts)
- during experiment loop to reset branch (present only in modified AI Researcher prompt file)

**Results**

Based from me eyebaling it over two nights codex gose from stopping after 5-8 experiments to stopping after 20-30 turns. This does not sovle the problem on its own, hence second hack...

## TMUX Watchdog

Idea: start codex in tmux terminal. Then external script, in a loop, checks the tmux session for inactivity. If inactivity is detected, watchdog injects "Please continue" to codex terminal. This works becasue when working, codex displayes flashy wave "Working" and incremental timer "32m 14s".

This is super ugly and hacky. I hate it, but works in time for something more proper to appear.

Side note: this (with modification?) may also work for other harnesses.

**How to use**

```bash
git clone git@github.com:karpathy/autoresearch.git
cd autoresearch
codex --yolo       # Accept 'trusted folder' prompt, so codex doesnt ask again later
```

Then:

```bash
tmux new-session -s codex_gpu1 'cd /path/to/folder/autoresearch && codex --yolo'
```

Then: normal interactive session, talk to it etc

After loop started, in a different terminal:

```bash
./agent_tmux_watchdog.sh codex_gpu1
```

At this point, watchdog will monitor for inactivity and inject "Please continue" if 600s inactivity window is crossed.

**Results**

After 7h two agents were still going.

