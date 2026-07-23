#!/usr/bin/env python3
"""
Claude Code statusline: model | context bar+% + token delta | cache % | total cost + turn delta

Reads Claude Code's hook JSON on stdin, prints one ANSI-styled status line on stdout.
Designed so that NOTHING the hook can send ever produces a traceback in the user's
terminal prompt — on any unexpected input it degrades to a plain fallback line.

Structured as small pure functions so tests can import and check them directly.

CLI:
    <hook json on stdin>        normal operation
    --selftest                  render a sample line (verify a deployed copy works)
    --help                      print usage and exit
"""
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

FALLBACK_LINE = "Claude Code (waiting for session data...)"

# --- Palette ---
BOLD = "\033[1m"
RESET = "\033[0m"
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[91m"
MAGENTA = "\033[35m"
WHITE = "\033[97m"
GRAY = "\033[90m"

# --- Color assignments --- change any value to restyle a tier; thresholds are below.
MODEL_NAME_COLOR = CYAN
PROMPT_COUNT_COLOR = GRAY
CTX_COLOR_OK, CTX_COLOR_WARN, CTX_COLOR_CRIT = GREEN, YELLOW, RED
TOKEN_COLOR_LOW, TOKEN_COLOR_MID, TOKEN_COLOR_HIGH = GRAY, MAGENTA, YELLOW
CACHE_COLOR_LOW, CACHE_COLOR_MID, CACHE_COLOR_HIGH = GRAY, CYAN, GREEN
TOTAL_COST_COLOR_OK, TOTAL_COST_COLOR_WARN, TOTAL_COST_COLOR_CRIT = WHITE, YELLOW, RED
TURN_COST_COLOR_OK, TURN_COST_COLOR_WARN, TURN_COST_COLOR_CRIT = GRAY, YELLOW, RED

# --- Thresholds --- all "value >= X" cutoffs.
CTX_PCT_YELLOW, CTX_PCT_RED = 60, 85  # context window used %
TOKEN_DELTA_MAGENTA, TOKEN_DELTA_YELLOW = (
    2000,
    8000,
)  # token delta (input+output tokens/turn)
CACHE_PCT_CYAN, CACHE_PCT_GREEN = 40, 70  # cache efficiency %
TOTAL_COST_YELLOW, TOTAL_COST_RED = 1, 5  # total session cost, USD
TURN_COST_YELLOW, TURN_COST_RED = 0.05, 0.25  # per-turn cost delta, USD (own scale)
STALE_CACHE_DAYS = 2  # prune this script's cache files older than N days

MODEL_NAME_MAX_LEN = (
    40  # guard against a pathologically long display_name blowing up the line
)

_NUM_RE = re.compile(r"^-?\d+(\.\d+)?$")
# Strip ANSI escape sequences and C0 control chars (incl. newlines) from untrusted
# string fields before embedding them in our own ANSI-styled output. Without this,
# a display_name containing "\033[..." could inject styling or, via "\n", break
# Claude Code's "first line of stdout only" contract.
_ANSI_CTRL_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|[\x00-\x1f\x7f]")


def is_num(v) -> bool:
    """True if v is a real (finite) number, or a string that looks like one."""
    if isinstance(v, bool):
        return False
    if isinstance(v, int):
        return True
    if isinstance(v, float):
        return v == v and v not in (  # pylint: disable=comparison-with-itself
            float("inf"),
            float("-inf"),
        )  # reject nan/inf
    if isinstance(v, str):
        return bool(_NUM_RE.match(v))
    return False


def to_num(v, default=0):
    """Coerce v to a finite number, falling back to default for anything else
    (non-numeric, nan, inf, bool, wrong type)."""
    if isinstance(v, bool):
        return default
    if isinstance(v, int):
        return v
    if isinstance(v, float):
        return v if is_num(v) else default
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


def sanitize_text(s, max_len=None) -> str:
    """Make an untrusted string safe to embed in our ANSI output: strip escape
    sequences / control chars, then optionally length-cap with an ellipsis."""
    if not isinstance(s, str):
        return ""
    cleaned = _ANSI_CTRL_RE.sub("", s)
    if max_len is not None and len(cleaned) > max_len:
        cleaned = cleaned[: max_len - 1] + "\u2026"
    return cleaned


def clean_session_id(session_id) -> str:
    """Sanitize session ID to alphanumeric, underscore, and hyphen characters."""
    if not isinstance(session_id, str):
        session_id = ""
    safe = re.sub(r"[^A-Za-z0-9_-]", "", session_id)
    return safe or "nosession"


def prune_stale_cache(cache_dir: Path, days: int) -> None:
    """Delete statusline cache files older than specified number of days."""
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


def tier_color(  # pylint: disable=too-many-arguments,too-many-positional-arguments
    value, t_mid, t_high, color_low, color_mid, color_high
) -> str:
    """Shared 3-tier threshold->color lookup used by every gauge in this file
    (context %, token delta, cache %, total cost, turn cost)."""
    if value >= t_high:
        return color_high
    if value >= t_mid:
        return color_mid
    return color_low


def compute_context_bar(pct: int):
    """10-block bar, rounded so 95-99% reads as a full bar, not stuck at 9/10."""
    filled = int((pct / 10) + 0.5)
    filled = max(0, min(10, filled))
    empty = 10 - filled
    bar_str = "\u25ae" * filled + "\u25af" * empty
    color = tier_color(
        pct, CTX_PCT_YELLOW, CTX_PCT_RED, CTX_COLOR_OK, CTX_COLOR_WARN, CTX_COLOR_CRIT
    )
    return bar_str, color


def human_size(n) -> str:
    """Format number as human-readable size (M for millions, k for thousands)."""
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
        delta_str = (
            f"\u2191{growth / 1000:.1f}k" if growth >= 1000 else f"\u2191{growth}"
        )
    color = tier_color(
        growth,
        TOKEN_DELTA_MAGENTA,
        TOKEN_DELTA_YELLOW,
        TOKEN_COLOR_LOW,
        TOKEN_COLOR_MID,
        TOKEN_COLOR_HIGH,
    )
    return growth, delta_str, color


def compute_cache_pct(cache_read, in_tok, cache_create):
    """Share of this turn's input served from cache. None if no cache activity
    at all (so the whole cache segment can be omitted)."""
    denom = cache_read + in_tok + cache_create
    if denom <= 0:
        return None
    return round((cache_read / denom) * 100)


def cache_pct_color(pct: int) -> str:
    """Get color for cache percentage based on thresholds."""
    return tier_color(
        pct,
        CACHE_PCT_CYAN,
        CACHE_PCT_GREEN,
        CACHE_COLOR_LOW,
        CACHE_COLOR_MID,
        CACHE_COLOR_HIGH,
    )


def total_cost_color(total_cost) -> str:
    """Get color for total session cost based on thresholds."""
    return tier_color(
        total_cost,
        TOTAL_COST_YELLOW,
        TOTAL_COST_RED,
        TOTAL_COST_COLOR_OK,
        TOTAL_COST_COLOR_WARN,
        TOTAL_COST_COLOR_CRIT,
    )


def turn_cost_color(turn_cost) -> str:
    """Get color for per-turn cost delta based on thresholds."""
    return tier_color(
        turn_cost,
        TURN_COST_YELLOW,
        TURN_COST_RED,
        TURN_COST_COLOR_OK,
        TURN_COST_COLOR_WARN,
        TURN_COST_COLOR_CRIT,
    )


def read_cache_file(path: Path) -> str:
    """Read cache file content, returning empty string on read failure."""
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def write_cache_file(path: Path, value: str) -> None:
    """Atomic write: write to a unique temp file in the same directory, then
    os.replace() into place. Prevents a torn/partial read when two Claude Code
    sessions sharing a session_id write concurrently. Never raises (read-only
    dir etc. is non-fatal for a statusline)."""
    try:
        fd, tmp = tempfile.mkstemp(prefix=".statusline-tmp-", dir=str(path.parent))
        try:
            with os.fdopen(fd, "w") as fh:
                fh.write(value)
            os.replace(tmp, str(path))
        except OSError:
            try:
                os.unlink(tmp)
            except OSError:
                pass
    except OSError:
        pass  # couldn't even create the temp file (read-only dir) — give up silently


def render(data: dict, cache_dir: Path) -> str:  # pylint: disable=too-many-locals
    """Given parsed hook JSON and a cache directory, return the finished ANSI
    status line. All stateful cache reads/writes (turn-cost delta, prompt
    counter) are scoped to cache_dir so tests can isolate them.

    This function assumes `data` is a dict; main() guarantees that. It aims never
    to raise, but render_safe() wraps it as a final backstop."""
    raw_model = safe_get(data, "model", "display_name")
    model = (
        sanitize_text(raw_model, MODEL_NAME_MAX_LEN)
        if isinstance(raw_model, str)
        else ""
    )
    if not model:
        model = "Claude"

    session_id = safe_get(data, "session_id") or "nosession"
    raw_prompt_id = safe_get(data, "prompt_id")
    prompt_id = raw_prompt_id if isinstance(raw_prompt_id, str) else ""

    pct_raw = safe_get(data, "context_window", "used_percentage")
    ctx_size = safe_get(data, "context_window", "context_window_size")
    out_tok = to_num(
        safe_get(data, "context_window", "current_usage", "output_tokens"), 0
    )
    in_tok = to_num(
        safe_get(data, "context_window", "current_usage", "input_tokens"), 0
    )
    cache_create = to_num(
        safe_get(
            data, "context_window", "current_usage", "cache_creation_input_tokens"
        ),
        0,
    )
    cache_read = to_num(
        safe_get(data, "context_window", "current_usage", "cache_read_input_tokens"), 0
    )
    total_cost = to_num(safe_get(data, "cost", "total_cost_usd"), 0)

    pct = max(0, min(100, int(to_num(pct_raw, 0))))

    session_id_safe = clean_session_id(session_id)
    prune_stale_cache(cache_dir, STALE_CACHE_DAYS)

    size_human = human_size(to_num(ctx_size, 0))

    _, token_delta_str, token_color = compute_token_delta(out_tok, in_tok, cache_create)
    cache_pct = compute_cache_pct(cache_read, in_tok, cache_create)

    cost_file = cache_dir / f"statusline-cost-{session_id_safe}"
    prev_cost = to_num(read_cache_file(cost_file), 0)
    turn_cost = max(0, total_cost - prev_cost)
    write_cache_file(cost_file, str(total_cost))

    count_file = cache_dir / f"statusline-promptcount-{session_id_safe}"
    lastid_file = cache_dir / f"statusline-promptlastid-{session_id_safe}"
    prompt_count = int(to_num(read_cache_file(count_file), 0))
    last_prompt_id = read_cache_file(lastid_file)
    if prompt_id and prompt_id != last_prompt_id:
        prompt_count += 1
        write_cache_file(count_file, str(prompt_count))
        write_cache_file(lastid_file, prompt_id)

    ctx_bar, bar_color = compute_context_bar(pct)

    size_part = f" of {size_human}" if size_human else ""
    token_part = f" {token_color}{token_delta_str}{RESET}" if token_delta_str else ""

    cache_part = ""
    if cache_pct is not None:
        cache_part = f" | {cache_pct_color(cache_pct)}cache {cache_pct}%{RESET}"

    total_fmt = f"${total_cost:.2f}"
    turn_fmt = f"${turn_cost:.2f}"
    turn_part = (
        f" {turn_cost_color(turn_cost)}\u2191{turn_fmt}{RESET}" if turn_cost > 0 else ""
    )

    return (
        f"{BOLD}{MODEL_NAME_COLOR}{model}{RESET} {PROMPT_COUNT_COLOR}#{prompt_count}{RESET} | "
        f"{bar_color}{ctx_bar} {pct}%{size_part}{RESET}{token_part}{cache_part} | "
        f"{total_cost_color(total_cost)}total {total_fmt}{RESET}{turn_part}"
    )


def render_safe(data: dict, cache_dir: Path) -> str:
    """Backstop wrapper: render() is written not to raise, but a statusline must
    NEVER emit a traceback into the user's prompt. If anything slips through,
    fall back to a plain line instead of crashing."""
    try:
        line = render(data, cache_dir)
    except Exception:  # pylint: disable=broad-exception-caught
        return FALLBACK_LINE
    # Final guard on the single-line contract: Claude Code shows only the first
    # line of stdout, so collapse any stray newline that survived sanitization.
    return line.split("\n", 1)[0]


def _resolve_cache_dir() -> Path:
    return Path(os.environ.get("TMPDIR", tempfile.gettempdir()))


def main(argv=None) -> int:
    """Parse CLI arguments and render statusline from stdin JSON or sample data."""
    argv = sys.argv[1:] if argv is None else argv
    if "--help" in argv or "-h" in argv:
        print((__doc__ or "").strip())
        return 0
    if "--selftest" in argv:
        sample = {
            "model": {"display_name": "Sonnet"},
            "session_id": "selftest",
            "prompt_id": "p1",
            "context_window": {
                "used_percentage": 72,
                "context_window_size": 200_000,
                "current_usage": {
                    "input_tokens": 3000,
                    "output_tokens": 500,
                    "cache_read_input_tokens": 9000,
                },
            },
            "cost": {"total_cost_usd": 2.35},
        }
        print(render_safe(sample, _resolve_cache_dir()))
        return 0

    try:
        raw = sys.stdin.read()
    except (OSError, KeyboardInterrupt):
        print(FALLBACK_LINE)
        return 0

    if not raw.strip():
        print(FALLBACK_LINE)
        return 0
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        print(FALLBACK_LINE)
        return 0
    if not isinstance(data, dict):
        data = {}

    print(render_safe(data, _resolve_cache_dir()))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        # stdout closed early (e.g. piped into `head`). Standard CLI hygiene:
        # redirect fd to devnull so the interpreter's shutdown flush doesn't
        # re-raise, then exit quietly.
        try:
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        except OSError:
            pass
        sys.exit(0)
