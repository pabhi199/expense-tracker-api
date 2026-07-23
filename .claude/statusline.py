#!/usr/bin/env python3
"""
Claude Code statusline: model | context bar+% + token delta | cache % | total cost + turn delta
Handles: malformed/empty JSON, absent fields, read-only /tmp, non-numeric values,
and null current_usage (before first API call / after /compact).

Drop-in replacement for statusline.sh — same stdin (hook JSON) -> stdout (ANSI line)
contract, same thresholds/colors/format. Structured as small pure functions so tests
can import and check them directly instead of only shelling out.
"""
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

# --- Palette ---
BOLD = "\033[1m"; RESET = "\033[0m"
CYAN = "\033[36m"; GREEN = "\033[32m"; YELLOW = "\033[33m"; RED = "\033[91m"
MAGENTA = "\033[35m"; WHITE = "\033[97m"; GRAY = "\033[90m"

# --- Color assignments --- change any value to restyle a tier; thresholds are below.
MODEL_NAME_COLOR = CYAN
PROMPT_COUNT_COLOR = GRAY
CTX_COLOR_OK, CTX_COLOR_WARN, CTX_COLOR_CRIT = GREEN, YELLOW, RED
TOKEN_COLOR_LOW, TOKEN_COLOR_MID, TOKEN_COLOR_HIGH = GRAY, MAGENTA, YELLOW
CACHE_COLOR_LOW, CACHE_COLOR_MID, CACHE_COLOR_HIGH = GRAY, CYAN, GREEN
TOTAL_COST_COLOR_OK, TOTAL_COST_COLOR_WARN, TOTAL_COST_COLOR_CRIT = WHITE, YELLOW, RED
TURN_COST_COLOR_OK, TURN_COST_COLOR_WARN, TURN_COST_COLOR_CRIT = GRAY, YELLOW, RED

# --- Thresholds --- all "value >= X" cutoffs.
CTX_PCT_YELLOW, CTX_PCT_RED = 60, 85            # context window used %
TOKEN_DELTA_MAGENTA, TOKEN_DELTA_YELLOW = 2000, 8000  # token delta (input+output tokens/turn)
CACHE_PCT_CYAN, CACHE_PCT_GREEN = 40, 70        # cache efficiency %
TOTAL_COST_YELLOW, TOTAL_COST_RED = 1, 5        # total session cost, USD
TURN_COST_YELLOW, TURN_COST_RED = 0.05, 0.25    # per-turn cost delta, USD (own scale)
STALE_CACHE_DAYS = 2                            # prune this script's cache files older than N days

_NUM_RE = re.compile(r"^-?\d+(\.\d+)?$")


def is_num(v) -> bool:
    """True if v is a number, or a string that looks like one."""
    if isinstance(v, bool):
        return False
    if isinstance(v, (int, float)):
        return True
    if isinstance(v, str):
        return bool(_NUM_RE.match(v))
    return False


def to_num(v, default=0):
    """Coerce v to a number, falling back to default for anything non-numeric."""
    if isinstance(v, bool):
        return default
    if isinstance(v, (int, float)):
        return v
    if isinstance(v, str) and is_num(v):
        return float(v) if "." in v else int(v)
    return default


def safe_get(d, *keys, default=None):
    """Nested dict lookup that tolerates missing keys and None intermediates
    (e.g. current_usage: null) without raising."""
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return default if cur is None else cur


def clean_session_id(session_id) -> str:
    safe = re.sub(r"[^A-Za-z0-9_-]", "", session_id or "")
    return safe or "nosession"


def prune_stale_cache(cache_dir: Path, days: int) -> None:
    cutoff = time.time() - days * 86400
    try:
        for f in cache_dir.glob("statusline-*"):
            try:
                if f.stat().st_mtime < cutoff:
                    f.unlink()
            except OSError:
                pass
    except OSError:
        pass


def compute_context_bar(pct: int):
    """10-block bar, rounded so 95-99% reads as a full bar, not stuck at 9/10."""
    filled = int((pct / 10) + 0.5)
    filled = max(0, min(10, filled))
    empty = 10 - filled
    bar = "▮" * filled + "▯" * empty
    if pct >= CTX_PCT_RED:
        color = CTX_COLOR_CRIT
    elif pct >= CTX_PCT_YELLOW:
        color = CTX_COLOR_WARN
    else:
        color = CTX_COLOR_OK
    return bar, color


def human_size(n) -> str:
    if n is None or n <= 0:
        return ""
    if n >= 1_000_000:
        return f"{int(n / 1_000_000)}M"
    if n >= 1000:
        return f"{int(n / 1000)}k"
    return str(int(n))


def compute_token_delta(out_tok, in_tok, cache_create):
    """Token delta: input + cache_creation + output this turn. cache_read is
    excluded — it's content already in context from an earlier turn being
    reused, not new growth."""
    growth = int(out_tok) + int(in_tok) + int(cache_create)
    delta_str = ""
    if growth > 0:
        delta_str = f"\u2191{growth / 1000:.1f}k" if growth >= 1000 else f"+{growth}"
    if growth >= TOKEN_DELTA_YELLOW:
        color = TOKEN_COLOR_HIGH
    elif growth >= TOKEN_DELTA_MAGENTA:
        color = TOKEN_COLOR_MID
    else:
        color = TOKEN_COLOR_LOW
    return growth, delta_str, color


def compute_cache_pct(cache_read, in_tok, cache_create):
    """Share of this turn's input served from cache. None if no cache activity
    at all (so the whole cache segment can be omitted)."""
    denom = cache_read + in_tok + cache_create
    if denom <= 0:
        return None
    return round((cache_read / denom) * 100)


def cache_pct_color(pct: int) -> str:
    if pct >= CACHE_PCT_GREEN:
        return CACHE_COLOR_HIGH
    if pct >= CACHE_PCT_CYAN:
        return CACHE_COLOR_MID
    return CACHE_COLOR_LOW


def total_cost_color(total_cost) -> str:
    if total_cost >= TOTAL_COST_RED:
        return TOTAL_COST_COLOR_CRIT
    if total_cost >= TOTAL_COST_YELLOW:
        return TOTAL_COST_COLOR_WARN
    return TOTAL_COST_COLOR_OK


def turn_cost_color(turn_cost) -> str:
    if turn_cost >= TURN_COST_RED:
        return TURN_COST_COLOR_CRIT
    if turn_cost >= TURN_COST_YELLOW:
        return TURN_COST_COLOR_WARN
    return TURN_COST_COLOR_OK


def read_cache_file(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def write_cache_file(path: Path, value: str) -> None:
    try:
        path.write_text(value)
    except OSError:
        pass  # read-only /tmp etc. — never fatal


def render(data: dict, cache_dir: Path) -> str:
    """Pure(ish) render: given parsed hook JSON and a cache directory, returns
    the finished ANSI statusline string. All the stateful cache reads/writes
    (turn-cost delta, prompt counter) live here, scoped to cache_dir, so tests
    can point at a throwaway directory for isolation."""
    model = safe_get(data, "model", "display_name") or "Claude"
    session_id = safe_get(data, "session_id") or "nosession"
    prompt_id = safe_get(data, "prompt_id") or ""
    pct_raw = safe_get(data, "context_window", "used_percentage")
    ctx_size = safe_get(data, "context_window", "context_window_size")
    out_tok = safe_get(data, "context_window", "current_usage", "output_tokens")
    in_tok = safe_get(data, "context_window", "current_usage", "input_tokens")
    cache_create = safe_get(data, "context_window", "current_usage", "cache_creation_input_tokens")
    cache_read = safe_get(data, "context_window", "current_usage", "cache_read_input_tokens")
    total_cost = safe_get(data, "cost", "total_cost_usd")

    out_tok = to_num(out_tok, 0)
    in_tok = to_num(in_tok, 0)
    cache_create = to_num(cache_create, 0)
    cache_read = to_num(cache_read, 0)
    total_cost = to_num(total_cost, 0)

    pct = int(to_num(pct_raw)) if is_num(pct_raw) else 0
    pct = max(0, min(100, pct))

    session_id_safe = clean_session_id(session_id)
    prune_stale_cache(cache_dir, STALE_CACHE_DAYS)

    size_human = human_size(to_num(ctx_size)) if ctx_size is not None and is_num(ctx_size) else ""

    growth, token_delta_str, token_color = compute_token_delta(out_tok, in_tok, cache_create)
    cache_pct = compute_cache_pct(cache_read, in_tok, cache_create)

    cost_file = cache_dir / f"statusline-cost-{session_id_safe}"
    prev_cost_raw = read_cache_file(cost_file)
    prev_cost = to_num(prev_cost_raw, 0) if is_num(prev_cost_raw) else 0
    turn_cost = max(0, total_cost - prev_cost)
    write_cache_file(cost_file, str(total_cost))

    count_file = cache_dir / f"statusline-promptcount-{session_id_safe}"
    lastid_file = cache_dir / f"statusline-promptlastid-{session_id_safe}"
    prompt_count_raw = read_cache_file(count_file)
    prompt_count = int(to_num(prompt_count_raw, 0)) if is_num(prompt_count_raw) else 0
    last_prompt_id = read_cache_file(lastid_file)
    if prompt_id and prompt_id != last_prompt_id:
        prompt_count += 1
        write_cache_file(count_file, str(prompt_count))
        write_cache_file(lastid_file, prompt_id)

    bar, bar_color = compute_context_bar(pct)

    size_part = f" of {size_human}" if size_human else ""
    token_part = f" {token_color}{token_delta_str}{RESET}" if token_delta_str else ""

    cache_part = ""
    if cache_pct is not None:
        cache_part = f" | {cache_pct_color(cache_pct)}cache {cache_pct}%{RESET}"

    total_fmt = f"${total_cost:.2f}"
    turn_fmt = f"${turn_cost:.2f}"
    turn_part = f" {turn_cost_color(turn_cost)}\u2191{turn_fmt}{RESET}" if turn_cost > 0 else ""

    return (
        f"{BOLD}{MODEL_NAME_COLOR}{model}{RESET} {PROMPT_COUNT_COLOR}#{prompt_count}{RESET} | "
        f"{bar_color}{bar} {pct}%{size_part}{RESET}{token_part}{cache_part} | "
        f"{total_cost_color(total_cost)}total {total_fmt}{RESET}{turn_part}"
    )


def main() -> None:
    raw = sys.stdin.read()
    if not raw.strip():
        print("Claude Code (waiting for session data...)")
        return
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        print("Claude Code (waiting for session data...)")
        return
    if not isinstance(data, dict):
        data = {}

    cache_dir = Path(os.environ.get("TMPDIR", tempfile.gettempdir()))
    print(render(data, cache_dir))


if __name__ == "__main__":
    main()
