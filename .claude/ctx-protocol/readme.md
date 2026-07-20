# ctx-tool — Context Management for Claude Code

**Know where your context stands. Never lose your work to compaction. Stay out of the degradation zone.**

ctx-tool is a lightweight companion for Claude Code that makes the context window visible, protects your session state with durable handoffs, and helps you avoid the two silent killers of long sessions: quality degradation and lossy compaction — all without getting in your way.

---

## Why this exists

Claude Code's context window is a black box until it isn't:

- **You don't see it filling up.** Context grows silently with every turn, every file read, every tool call — until auto-compaction fires mid-task, or worse, overshoots and leaves you with `/clear` as the only way out.
- **Quality degrades before you hit the limit.** Model performance measurably drops well before the window is technically full. Running at 85% context isn't "getting your money's worth" — it's getting worse answers.
- **Compaction summaries are lossy and ephemeral.** What compaction keeps lives only inside the session. Close the terminal, crash, or `/clear` — and it's gone. Decisions, unresolved items, the "why" behind your changes: unrecoverable.
- **Long sessions quietly cost more.** Even with prompt caching, every turn re-bills your entire accumulated history. A session that has crept to 120K tokens pays roughly 6× more per turn in cache reads than one at 20K.

ctx-tool addresses all four with one principle: **the statusline is the interface, messages are for emergencies, and nothing ever touches your context unless you explicitly ask.**

---

## What it does

### 1. Live context statusline

A single always-visible line, color-coded by *quality zone* — not just raw fill:

```
▮▮▮▮▮▯▯▯ 54% of 200K | git:(main) | ≈9 turns | 4.1k tok/turn | $1.84
```

| Field | Meaning |
|---|---|
| Context bar + % of window | How full the window is (and whether you're on a 200K or 1M window) — the bar's color *is* the zone (green/yellow/red), no redundant text label |
| git branch | Current branch, when the statusline's cwd is inside a git repo |
| ≈ turns left | Forecast to auto-compact, based on your *recent* burn rate (rolling 5-turn window) |
| tok/turn | Average tokens per turn — flips color when a spike (big file reads) is detected |
| $ | Session cost so far |

The `%` and window size come straight from Claude Code's own statusline data on every render — nothing here is a manual estimate. (The only manual, approximate percentage anywhere in ctx-protocol lives inside the hooks that decide when to auto-save a red-zone handoff, since hook payloads don't carry the real context window size — that number is intentionally never shown or logged, only used as a rough trigger.)

**Zones:** green below 50%, yellow 50–70%, red above 70% (all configurable). Yellow is a visual signal only — no interruptions. Red is where the tool acts.

### 2. Durable handoffs (`handoff.md`)

A structured, human-readable snapshot of your working state — what you were doing, decisions made, unresolved items, files touched. Kept **one per project + git branch**, stored inside your project but never committed.

Handoffs are written automatically and silently at the moments that matter:

- **Entering the red zone** — insurance *before* compaction risk becomes real
- **Right before compaction** (manual or auto) — so nothing is lost to the summary
- **Session end** — so tomorrow-you starts where today-you stopped

Unlike compaction's in-context summary, a handoff survives crashes, closed terminals, and `/clear`. It's a real file you can read, edit, or share.

### 3. Complete per-turn logging

Every turn is appended to a per-session `turns.jsonl` — tokens in/out, cache reads/writes, model, tools used, files touched, and compaction events. This is the raw data layer behind the statusline and forecasts, and yours to analyze however you like. (Per-turn cost and context % aren't logged: hook payloads never carry cost, and the only context-window-size hooks can assume is a rough guess — accurate enough to trigger the red-zone insurance write, not accurate enough to persist as fact. The live statusline gets the real numbers straight from Claude Code.)

### 4. Three one-line notices — and nothing more

ctx-tool speaks at most three times per session, one line each, asked once and never repeated:

1. **Entering red:** `⚠ context is getting full — handoff saved. /compact or /clear recommended.`
2. **After compaction:** `Compacted. /resume-handoff to restore task state.`
3. **Session start (handoff found for your branch):** `Handoff for feature-auth-fix (2h old): "fixing token refresh, tests 3/5 passing" — /resume-handoff to load.`

No reminders. No dialogs. No auto-injection. If you ignore a notice, the colored statusline remains as the ambient signal — that's it.

---

## How it's useful (in practice)

- **Cheaper sessions.** Wrapping up around the yellow/red boundary and restarting with a ~500-token handoff instead of dragging 120K tokens of history cuts recurring per-turn cost dramatically — the handoff replaces the history, not the work.
- **Better answers.** Staying in the green/yellow range keeps you out of the measured degradation zone where models start forgetting early instructions.
- **Crash-proof continuity.** Laptop died mid-task? The handoff and turn log are already on disk. `/resume-handoff` in a fresh session and continue.
- **Branch-aware memory.** Check out a branch you haven't touched in three days and be greeted with exactly that task's state — not a generic project summary.
- **Zero fingerprints.** Nothing appears in `git status`, no `.gitignore` edits, no transcript clutter. The tool ignores itself via `.git/info/exclude`, which is local to your clone.

---

## How to use

### Install

Copy the `ctx-protocol/` folder into any project at `<project>/.claude/ctx-protocol/`, then run:

```bash
bash .claude/ctx-protocol/install.sh
```

This wires ctx-protocol into that project: it additively merges the statusLine, hooks, and permission rules it needs into `.claude/settings.json` (existing hooks and statusline, if any, are left untouched), installs the `handoff` / `resume-handoff` / `ctx-settings` skills into `.claude/skills/`, and adds `.claude/ctx-protocol/data/` to `.git/info/exclude`. Safe to re-run — every change is additive and matched by exact content, so running it twice never duplicates anything.

To remove everything it added: `bash .claude/ctx-protocol/install.sh --uninstall` (reproduces the exact pre-install state; doesn't delete the `ctx-protocol/` folder itself).

Everything ctx-protocol owns — scripts, skill definitions, settings, runtime data — lives inside `.claude/ctx-protocol/`. The installer only touches `.claude/settings.json`, `.claude/skills/`, and `.git/info/exclude` because Claude Code requires hooks/statusLine and skills at those fixed locations; nothing else in the project is touched.

### Day-to-day

You mostly do nothing. Watch the statusline color:

| You see | It means | Do (if you want) |
|---|---|---|
| Green bar | Plenty of room | Nothing |
| Yellow bar | Past 50% — plan a good stopping point | Optionally `/handoff` + `/compact` at a natural boundary |
| Red bar + one-line notice | Handoff already saved for you | `/compact` to continue here, or `/clear` and `/resume-handoff` in a fresh session |

### Skills

Implemented as `.claude/skills/*/SKILL.md`, invoked the same way as any other skill or slash command:

| Command | What it does |
|---|---|
| `/handoff` | Snapshot your working state right now (before lunch, before a risky refactor) |
| `/resume-handoff` | Inject the latest handoff for the current project + branch into the session — **the only way ctx-tool ever adds anything to your context** |
| `/ctx-settings` | Show the effective settings and edit the local override for you |

### Configure (optional)

Shipped defaults live in `.claude/ctx-protocol/settings.default.json`; per-project overrides in `.claude/ctx-protocol/data/settings.local.json` (created on first edit, git-excluded). `/ctx-settings` shows the effective merge and edits the override for you.

```json
{
  "zones": { "yellow_pct": 50, "red_pct": 70 },
  "notices": { "on_red": true, "on_post_compact": true, "on_session_start": true },
  "auto_inject": { "post_compact": false, "session_start": false },
  "handoff": {
    "keep_backup": true,
    "store_in_repo": false,
    "model": "haiku",
    "max_summary_tokens": 800,
    "transcript_tail_lines": 400
  },
  "statusline": {
    "enabled": true, "show_cost": true, "show_burn_rate": true, "auto_compact_pct": 92
  },
  "log": { "retention_days": 30 }
}
```

Handoffs are always scoped to project + git branch — one file per branch, no separate scope knob.

Notable knobs:

- **`zones`** — move the thresholds; red is always clamped below your auto-compact trigger so there's room to act.
- **`notices`** — turn any of the three one-liners off individually.
- **`auto_inject`** — off by default; opt in if you want handoffs restored automatically after compaction or at session start.
- **`handoff.model`** — summaries run on Haiku by default, so generating them costs next to nothing.
- **`handoff.store_in_repo`** — opt in to commit handoffs so teammates pulling your branch inherit your context.

### Where things live

```
<project-root>/.claude/ctx-protocol/         ← the whole tool, self-contained
├── readme.md
├── install.sh                  ← wires it into a project (see Install, above)
├── settings.default.json
├── settings.fragment.json      ← statusLine/hooks/permissions install.sh merges in
├── scripts/                    ← statusline, hooks, handoff generation
├── skills/                     ← handoff / resume-handoff / ctx-settings source
└── data/                       ← runtime state, created lazily, git-excluded
    ├── handoffs/
    │   ├── main.md              ← one per branch, previous version kept as .md.1
    │   └── feature-auth-fix.md
    ├── sessions/<session_id>/
    │   └── turns.jsonl          ← complete per-turn log the statusline forecasts from
    ├── settings.local.json      ← optional per-project overrides
    └── error.log
```

`data/` is excluded from git automatically via `.git/info/exclude` (added by `install.sh`) — local to your clone, invisible to teammates, no `.gitignore` diff to explain in code review. Everything else in this tree ships with the project like any other tool.

---

## Design principles

1. **Invisible by default.** No transcript clutter, no repo fingerprints, no behavior changes you didn't ask for.
2. **Context is sacred.** Only an explicit `/resume-handoff` ever adds anything to the model's context. Hooks may *say* things (once, as a notice); they never *put* things — unless you opt into `auto_inject`.
3. **Insurance before advice.** When risk is real (red zone, pre-compaction), the durable snapshot is written *first*, unconditionally — then you're told. Advice can be ignored; insurance can't be optional.
4. **Never break the session.** Every hook fails silently to a local error log. A bug in ctx-tool must never interrupt your work.

---

## Status

v1 spec — under active development. Roadmap candidates: forgotten-instruction tracking, secret-leak scanning of tool output, quota-anomaly detection, and cross-session search over turn logs.