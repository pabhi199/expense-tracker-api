# Claude Code Statusline

A single-line, color-coded statusline for [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) that shows the model, context window usage, token throughput, prompt-cache efficiency, and session cost — all computed from the JSON Claude Code pipes into the script on every render.

```
Sonnet 4.6 #12 | ▮▮▮▮▮▮▯▯▯▯ 65% of 200k +2.4k | cache 82% | total $3.40 ↑$0.18
```

---

## Table of contents

- [What it shows](#what-it-shows)
- [Installation](#installation)
- [Requirements](#requirements)
- [Metrics, in detail](#metrics-in-detail)
- [Configuration](#configuration)
- [How state is remembered between renders](#how-state-is-remembered-between-renders)
- [Performance](#performance)
- [Design principles](#design-principles)
- [Troubleshooting](#troubleshooting)

---

## What it shows

Reading left to right:

| Segment | Example | Meaning |
|---|---|---|
| Model name | `Sonnet 4.6` | Current model, always fresh from that render's JSON |
| Prompt counter | `#12` | Number of distinct user prompts seen this session |
| Context bar | `▮▮▮▮▮▮▯▯▯▯ 65% of 200k` | Context window used, with size |
| Token delta | `+2.4k` | Fresh tokens (not reused from cache) added this turn |
| Cache % | `cache 82%` | Share of this turn's input served from prompt cache |
| Total cost | `total $3.40` | Session cost so far, from Claude Code's own estimate |
| Turn cost | `↑$0.18` | How much *this turn* added to the total |

Every colored segment uses the same rule: **green/neutral = fine, yellow = notice, red = act**. Colors are never assigned arbitrarily — see [Configuration](#configuration) for exactly how each threshold maps to a color.

---

## Installation

1. Save the script, e.g. to `~/.claude/statusline.sh`.
2. Make it executable:
   ```bash
   chmod +x ~/.claude/statusline.sh
   ```
3. Point Claude Code at it in `~/.claude/settings.json` (or your project's `.claude/settings.json`):
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline.sh"
     }
   }
   ```
4. Settings reload automatically, but the new statusline won't appear until your next interaction with Claude Code.

You can also generate/attach a statusline via the built-in slash command:
```
/statusline show model, context %, token delta, cache %, and cost
```

### Test it manually

The script reads JSON from stdin, so you can test it without Claude Code at all:

```bash
echo '{"model":{"display_name":"Test"},"session_id":"abc","prompt_id":"p1","context_window":{"used_percentage":45,"context_window_size":200000,"current_usage":{"output_tokens":500,"input_tokens":200,"cache_creation_input_tokens":100,"cache_read_input_tokens":8000}},"cost":{"total_cost_usd":0.15}}' | ~/.claude/statusline.sh
```

---

## Requirements

- **`jq`** — required. Without it, the script prints a one-line message telling you to install it, rather than crashing or printing nothing (`sudo apt install jq`, `brew install jq`, etc.).
- **`bash`** and **`awk`** — present on essentially every macOS/Linux install by default. On Windows, Claude Code runs statusline commands through Git Bash when available, or PowerShell otherwise (a native PowerShell port isn't included here, but the JSON contract is the same).
- Read/write access to `/tmp` (or `$TMPDIR`) — used for a few small persistence files (see [below](#how-state-is-remembered-between-renders)). The script degrades gracefully if this isn't writable — you just lose the turn-cost delta and prompt counter, everything else still works.

---

## Metrics, in detail

### Context window %
Pulled directly from Claude Code's own `context_window.used_percentage` field and never recomputed — that field already accounts for input, cache-read, and cache-creation tokens the way Anthropic's API actually bills them, so recalculating it independently would just be a chance to get it wrong. The script only clamps it to `0–100` and rounds the bar to the nearest of 10 blocks (so 95–99% shows a full bar instead of looking stuck one block short).

### Token delta
```
delta = input_tokens + cache_creation_input_tokens + output_tokens
```
This is deliberately **not** just `output_tokens`, and **not** all four usage fields summed. The reasoning:

- `cache_read_input_tokens` — content already sitting in context from an earlier turn, now just being re-served from cache. It was already counted as growth on a previous render, so counting it again here would double-count old ground.
- `input_tokens` and `cache_creation_input_tokens` — both represent genuinely *new* content this turn (the difference between them is purely which caching bucket the prompt-builder routed each chunk into, not whether it's new).
- `output_tokens` — the response itself, which becomes part of context for the next turn.

So the formula above is the accurate answer to "how much did context actually grow this turn," matching the same three fields Anthropic's own `used_percentage` calculation uses (input + cache_creation + cache_read), minus the one bucket that isn't new.

### Cache efficiency %
```
cache % = cache_read_input_tokens / (cache_read_input_tokens + input_tokens + cache_creation_input_tokens) × 100
```
This answers "of all the input tokens this turn, what fraction were served cheaply from cache instead of paid for at full price?" It's independent of the token-delta calculation above — a turn can have a small delta (little new growth) and a high cache % (most of a big prompt was reused), or vice versa. If all three denominator fields are zero (no input activity at all that turn — e.g. a pure tool-only step), the segment is omitted rather than showing a misleading `cache 0%`.

### Total cost
Read straight from Claude Code's `cost.total_cost_usd`, which the docs note **resets to `$0` when `/clear` starts a new session** (from Claude Code v2.1.211+). No special-casing needed here — the field just reports whatever Claude Code says the session has cost so far.

### Turn cost delta
```
turn cost = max(0, total_cost_usd_now − total_cost_usd_previous_render)
```
Since Claude Code only exposes the *running total*, the per-turn cost has to be derived by diffing against the last value the script itself saw and saved. The result is clamped to a minimum of `0` — this is what makes a `/clear` (which resets the total to `$0`) show *no* turn-cost arrow at all on that render, instead of a nonsensical negative number.

### Prompt counter
Increments only when `prompt_id` changes from the last one seen — **not** on every render. This matters because the statusline re-renders on several events that aren't a new user prompt (a `refreshInterval` timer tick, `/compact` finishing, a permission-mode change, vim-mode toggling). A genuinely new `prompt_id` is Claude Code's own signal that a new prompt was submitted — in practice this includes model-picker confirmations and similar in-CLI submissions, not just chat messages, so the counter reflects "distinct submitted inputs this session" rather than narrowly "chat turns."

---

## Configuration

Every visual choice lives in one of three blocks near the top of the script — nothing else in the logic below ever needs to change.

### 1. Palette — raw colors
```bash
BOLD=$'\033[1m'; RESET=$'\033[0m'
CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[91m'
MAGENTA=$'\033[35m'; WHITE=$'\033[97m'; GRAY=$'\033[90m'
```
Swap any value for another ANSI code. Reference:

| | Black | Red | Green | Yellow | Blue | Magenta | Cyan | White |
|---|---|---|---|---|---|---|---|---|
| Normal | 30 | 31 | 32 | 33 | 34 | 35 | 36 | 37 |
| Bright | 90 | 91 | 92 | 93 | 94 | 95 | 96 | 97 |

Format is `\033[<code>m`, e.g. `\033[94m` for bright blue. Always keep `RESET=$'\033[0m'`.

### 2. Color assignments — which color means what
```bash
CTX_COLOR_OK="$GREEN";  CTX_COLOR_WARN="$YELLOW";  CTX_COLOR_CRIT="$RED"
TOKEN_COLOR_LOW="$GRAY"; TOKEN_COLOR_MID="$MAGENTA"; TOKEN_COLOR_HIGH="$YELLOW"
# ...and similarly for cache %, total cost, turn cost
```
Every *measurement* (context %, token delta, cache %, total cost, turn cost) has three tiers you can repoint to any palette color independently. Only the model name and `#N` counter are fixed, non-threshold colors, since they're identity labels, not severity signals.

### 3. Thresholds — where each tier kicks in
```bash
CTX_PCT_YELLOW=60;      CTX_PCT_RED=85          # context window used %
TOKEN_DELTA_MAGENTA=2000; TOKEN_DELTA_YELLOW=8000 # token delta, raw tokens
CACHE_PCT_CYAN=40;      CACHE_PCT_GREEN=70       # cache efficiency %
TOTAL_COST_YELLOW=1;    TOTAL_COST_RED=5         # total session cost, USD
TURN_COST_YELLOW=0.05;  TURN_COST_RED=0.25       # per-turn cost delta, USD
STALE_CACHE_DAYS=2                               # /tmp file cleanup window
```
All thresholds are "greater than or equal to" cutoffs. Turn-cost thresholds are deliberately on their own, much smaller scale than total-cost thresholds — a $0.30 turn is worth flagging even in an otherwise cheap session, and trivial in an expensive one.

---

## How state is remembered between renders

Each statusline render is a brand-new, disconnected process — Claude Code spawns it, pipes in that turn's JSON, reads one line of stdout, and the process exits. Nothing survives in memory between one render and the next; there's no way for a bash variable to "remember" a previous run, because there is no previous run from that process's point of view.

Two metrics need a previous value to compute a delta, so the script persists exactly three small files per session in `$TMPDIR` (or `/tmp`), named using the sanitized `session_id`:

```
statusline-cost-<session_id>          # last-seen total_cost_usd, for the turn-cost delta
statusline-promptcount-<session_id>   # running prompt count (#N)
statusline-promptlastid-<session_id>  # last prompt_id seen, to detect a genuinely new prompt
```

**Cleanup:** on every render, the script deletes any of its own files older than `STALE_CACHE_DAYS` (default 2). This is the only mechanism available — there's no "session ended" event a script can hook into, so a file simply aging out unrefreshed is the signal that a session is no longer active. If every session were closed and none run again, cleanup would stop happening too (nothing left to trigger it) — but the next time *any* session starts anywhere, that render's cleanup pass sweeps out everything from the abandoned sessions.

**If `/tmp` is read-only:** every write is wrapped in `|| true`, so a failed write is silently ignored. Worst case, the prompt counter stays at `#1` and the turn-cost arrow never appears — everything else (context %, token delta, cache %, total cost) still renders correctly, since those come straight from that render's JSON with no memory required.

---

## Performance

The script is optimized to minimize subprocess forks, since it can run as often as every 300ms during active use, and Claude Code cancels an in-flight render outright if a new update trigger fires before it finishes.

- **One `jq` call, not ten.** All fields are extracted in a single query, joined with the ASCII unit-separator character (`\x1f`) rather than a tab or space — bash's `read` silently collapses consecutive tab/space delimiters, which would corrupt parsing on any render with empty fields (e.g. `current_usage: null`).
- **Numeric validation uses bash's native regex (`[[ =~ ]])`**, not a forked `awk` process.
- Floating-point math (percentages, cost formatting, rounding) still goes through `awk`, since bash has no native decimal arithmetic — this is the one place forking is unavoidable without adding an extra dependency like `bc`.

Net effect measured in testing: **~107ms → ~51ms per render**, roughly halved, with fork count per render dropping from 38 to 20.

---

## Design principles

A few decisions worth knowing if you're extending this script:

1. **Trust server-computed fields over recomputing them.** `used_percentage` and `total_cost_usd` are used as-is; nothing here tries to second-guess Anthropic's own math.
2. **Color encodes severity, not identity.** A given color (e.g. yellow) means the same thing everywhere it appears — "this number deserves a second look" — rather than each segment picking its own permanent, decorative color.
3. **Silently degrade, never crash or hang.** Missing fields, malformed JSON, non-numeric values, a missing `jq`, or a read-only `/tmp` all produce a sensible partial or fallback output rather than an error or a stalled render.
4. **Every persisted number is clamped defensively** (turn-cost delta can't go negative, context % can't exceed 100, etc.) so a `/clear`, a `/compact`, or an unexpected value from Claude Code itself can't produce a nonsensical display.

---

## Troubleshooting

**Statusline not appearing at all**
- Confirm the script is executable: `chmod +x ~/.claude/statusline.sh`
- Run it manually with mock JSON (see [Installation](#installation)) to check for errors
- Run `claude --debug` to see the exit code and stderr from the first invocation

**Shows "Claude Code (install jq for full statusline)"**
- Install `jq`: `sudo apt install jq` / `brew install jq` / your platform's package manager

**Shows "Claude Code (waiting for session data...)"**
- Normal very early in a session before the first JSON arrives; if it persists, check that Claude Code is actually piping valid JSON (run the script manually with real session JSON to confirm)

**Token delta, cache %, or turn cost never show up**
- These segments are all conditionally omitted when there's nothing meaningful to show (e.g. `current_usage` is `null` before the first API call, or right after `/compact`) — this is expected, not a bug

**Prompt counter stuck at `#1`**
- Check that `$TMPDIR` (or `/tmp`) is writable — the counter can't persist without it
- A model switch via `/model` does *not* bump the counter on its own turn if it doesn't get a new `prompt_id`; behavior here follows whatever `prompt_id` Claude Code assigns, which is outside this script's control
