"""
Regression tests for statusline.py.

Two tiers, both worth keeping:
  1. Unit tests import functions directly -> no subprocess, no ANSI stripping,
     runs in milliseconds, and pinpoints exactly which piece of logic broke.
  2. A handful of integration tests still go through the real CLI (stdin/stdout,
     env, filesystem) to prove the pieces are wired together correctly.

Run:
    pytest test_statusline_py.py -v
    pytest test_statusline_py.py -k "token"
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import statusline as sl  # noqa: E402

SCRIPT = Path(__file__).parent / "statusline.py"

_ANSI = re.compile(r"\x1B\[[0-9;]*[a-zA-Z]")


def strip_ansi(s: str) -> str:
    return _ANSI.sub("", s)


# ---------------------------------------------------------------------------
# Tier 1: unit tests on pure functions (no subprocess at all)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "value,expected",
    [
        (60, 60),
        (60.5, 60.5),
        ("60", 60),
        ("60.5", 60.5),
    ],
)
def test_to_num_parses_valid_numbers(value, expected):
    assert sl.to_num(value) == expected


@pytest.mark.parametrize(
    "value",
    [
        "oops",
        None,
        "",
        True,
        float("inf"),
        float("-inf"),
        float("nan"),
    ],
)
def test_to_num_falls_back_on_invalid(value):
    sentinel = object()
    assert sl.to_num(value, sentinel) is sentinel


@pytest.mark.parametrize("pct,expected_pct", [(150, 100), (-20, 0), (72, 72)])
def test_pct_clamping_via_render(pct, expected_pct, tmp_path):
    data = {
        "session_id": "s",
        "prompt_id": "p",
        "context_window": {"used_percentage": pct},
    }
    out = sl.render(data, tmp_path)
    assert f"{expected_pct}%" in out


@pytest.mark.parametrize(
    "pct,expected_color",
    [
        (59, sl.GREEN),
        (60, sl.YELLOW),
        (84, sl.YELLOW),
        (85, sl.RED),
    ],
)
def test_context_bar_color_thresholds(pct, expected_color):
    _, color = sl.compute_context_bar(pct)
    assert color == expected_color


@pytest.mark.parametrize("pct", [95, 99, 100])
def test_context_bar_rounds_to_full(pct):
    bar_str, _ = sl.compute_context_bar(pct)
    assert bar_str == "▮" * 10


@pytest.mark.parametrize(
    "size,expected",
    [(200_000, "200k"), (1_500_000, "1M"), (500, "500"), (0, ""), (None, "")],
)
def test_human_size(size, expected):
    assert sl.human_size(size) == expected


@pytest.mark.parametrize(
    "out_tok,in_tok,cache_create,expected_str,expected_color",
    [
        (50, 100, 0, "↑150", sl.GRAY),
        (0, 999, 0, "↑999", sl.GRAY),  # just under the k-format threshold
        (
            0,
            1999,
            0,
            "\u21912.0k",
            sl.GRAY,
        ),  # k-format, but still gray (color threshold is 2000)
        (0, 2000, 0, "\u21912.0k", sl.MAGENTA),
        (0, 8000, 0, "\u21918.0k", sl.YELLOW),
        (0, 0, 0, "", sl.GRAY),
    ],
)
def test_compute_token_delta(
    out_tok, in_tok, cache_create, expected_str, expected_color
):
    _, delta_str, color = sl.compute_token_delta(out_tok, in_tok, cache_create)
    assert delta_str == expected_str
    assert color == expected_color


def test_cache_read_excluded_from_growth():
    growth, delta_str, _ = sl.compute_token_delta(out_tok=0, in_tok=100, cache_create=0)
    # cache_read isn't even a parameter here by design -- growth must ignore it entirely
    assert growth == 100
    assert delta_str == "↑100"


@pytest.mark.parametrize(
    "cache_read,in_tok,cache_create,expected",
    [
        (0, 0, 0, None),
        (50, 50, 0, 50),
        (75, 25, 0, 75),
    ],
)
def test_compute_cache_pct(cache_read, in_tok, cache_create, expected):
    assert sl.compute_cache_pct(cache_read, in_tok, cache_create) == expected


@pytest.mark.parametrize(
    "cost,expected", [(0.50, sl.WHITE), (1.00, sl.YELLOW), (5.00, sl.RED)]
)
def test_total_cost_color(cost, expected):
    assert sl.total_cost_color(cost) == expected


@pytest.mark.parametrize(
    "cost,expected", [(0.01, sl.GRAY), (0.05, sl.YELLOW), (0.25, sl.RED)]
)
def test_turn_cost_color(cost, expected):
    assert sl.turn_cost_color(cost) == expected


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("abc/../def", "abcdef"),
        ("safe-id_123", "safe-id_123"),
        ("", "nosession"),
        (None, "nosession"),
    ],
)
def test_clean_session_id(raw, expected):
    assert sl.clean_session_id(raw) == expected


def test_to_num_rejects_bool():
    # bool is technically an int subclass in Python -- must not be treated as numeric
    assert sl.to_num(True, default=99) == 99
    assert sl.to_num(False, default=-1) == -1


@pytest.mark.parametrize(
    "pct,expected_color",
    [
        (39, sl.GRAY),
        (40, sl.CYAN),
        (69, sl.CYAN),
        (70, sl.GREEN),
    ],
)
def test_cache_pct_color_thresholds(pct, expected_color):
    assert sl.cache_pct_color(pct) == expected_color


def test_prune_stale_cache_deletes_old_files_only(tmp_path):
    old_file = tmp_path / "statusline-cost-old"
    fresh_file = tmp_path / "statusline-cost-fresh"
    unrelated_file = tmp_path / "not-ours.txt"
    old_file.write_text("1.00")
    fresh_file.write_text("2.00")
    unrelated_file.write_text("keep me")

    # backdate old_file's mtime beyond the staleness window
    stale_time = time.time() - (sl.STALE_CACHE_DAYS + 1) * 86400
    os.utime(old_file, (stale_time, stale_time))

    sl.prune_stale_cache(tmp_path, sl.STALE_CACHE_DAYS)

    assert not old_file.exists()  # stale statusline-* file: pruned
    assert fresh_file.exists()  # fresh statusline-* file: kept
    assert unrelated_file.exists()  # non-statusline file: never touched


def test_write_cache_file_swallows_oserror(tmp_path):
    # Point at a path whose parent doesn't exist -> write_text raises OSError
    bad_path = tmp_path / "no" / "such" / "dir" / "file"
    sl.write_cache_file(bad_path, "value")  # must not raise
    assert not bad_path.exists()


# ---------------------------------------------------------------------------
# Tier 1b: render() with an in-memory tmp_path -- still no subprocess, but
# exercises the full assembly + stateful cache-file logic together.
# ---------------------------------------------------------------------------


def test_null_current_usage_does_not_crash(tmp_path):
    data = {
        "model": {"display_name": "Sonnet"},
        "session_id": "s2",
        "prompt_id": "p1",
        "context_window": {"used_percentage": 10, "current_usage": None},
        "cost": {"total_cost_usd": 0},
    }
    assert "Sonnet" in sl.render(data, tmp_path)


def test_missing_context_window(tmp_path):
    data = {"model": {"display_name": "X"}, "session_id": "s3", "prompt_id": "p1"}
    assert "0%" in sl.render(data, tmp_path)


def test_non_numeric_used_percentage(tmp_path):
    data = {
        "session_id": "s4",
        "prompt_id": "p1",
        "context_window": {"used_percentage": "oops"},
    }
    assert "0%" in sl.render(data, tmp_path)


def test_non_numeric_cost(tmp_path):
    data = {"session_id": "s5", "prompt_id": "p1", "cost": {"total_cost_usd": "NaN"}}
    assert "total $0.00" in sl.render(data, tmp_path)


def test_turn_cost_delta_across_calls(tmp_path):
    sl.render(
        {"session_id": "st1", "prompt_id": "p1", "cost": {"total_cost_usd": 1.00}},
        tmp_path,
    )
    out = sl.render(
        {"session_id": "st1", "prompt_id": "p2", "cost": {"total_cost_usd": 1.30}},
        tmp_path,
    )
    assert "\u2191$0.30" in out


def test_turn_cost_never_negative_after_reset(tmp_path):
    sl.render(
        {"session_id": "st2", "prompt_id": "p1", "cost": {"total_cost_usd": 3.00}},
        tmp_path,
    )
    out = sl.render(
        {"session_id": "st2", "prompt_id": "p2", "cost": {"total_cost_usd": 0}},
        tmp_path,
    )
    assert "\u2191$-" not in out


def test_prompt_counter_dedupes_and_increments(tmp_path):
    o1 = sl.render({"session_id": "st3", "prompt_id": "pA"}, tmp_path)
    o2 = sl.render(
        {"session_id": "st3", "prompt_id": "pA"}, tmp_path
    )  # repeat, no bump
    o3 = sl.render({"session_id": "st3", "prompt_id": "pB"}, tmp_path)  # new, bumps
    assert "#1" in o1 and "#1" in o2 and "#2" in o3


def test_readonly_cache_dir_does_not_crash(tmp_path):
    ro = tmp_path / "ro"
    ro.mkdir()
    ro.chmod(0o555)
    try:
        out = sl.render(
            {"session_id": "ro1", "prompt_id": "p1", "cost": {"total_cost_usd": 2.00}},
            ro,
        )
        assert "total $2.00" in out
    finally:
        ro.chmod(0o755)


# ---------------------------------------------------------------------------
# Tier 2: integration tests through the real CLI (stdin -> stdout)
# ---------------------------------------------------------------------------


def run_cli(payload, tmp_path) -> str:
    stdin_data = payload if isinstance(payload, str) else json.dumps(payload)

    env = os.environ.copy()
    env["TMPDIR"] = str(tmp_path)
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=stdin_data,
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
        check=True,
    )
    return result.stdout + result.stderr


def run_cli_args(args) -> str:
    """Run the CLI with flags (no stdin needed for --version/--selftest/--help)."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        input="",
        capture_output=True,
        text=True,
        timeout=10,
        check=True,
    )
    return result.stdout + result.stderr


def test_cli_empty_input(tmp_path):
    assert "waiting for session data" in run_cli("", tmp_path)


def test_cli_malformed_json(tmp_path):
    assert "waiting for session data" in run_cli("{not valid json", tmp_path)


def test_cli_full_roundtrip(tmp_path):
    payload = {
        "model": {"display_name": "Sonnet"},
        "session_id": "cli1",
        "prompt_id": "p1",
        "context_window": {"used_percentage": 42},
        "cost": {"total_cost_usd": 0.10},
    }
    out = run_cli(payload, tmp_path)
    assert "Sonnet" in out and "42%" in out and "total $0.10" in out


def test_exact_output_format_snapshot(tmp_path):
    """Locks the full assembled string for a canonical input. Substring checks
    elsewhere won't catch a spacing/ordering regression (e.g. ' | ' -> ' |');
    this test will. If this fails after an intentional format change, update
    the expected string here deliberately -- don't just delete the test."""
    data = {
        "model": {"display_name": "Sonnet"},
        "session_id": "snap1",
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
    out = sl.render(data, tmp_path)
    expected = (
        f"{sl.BOLD}{sl.CYAN}Sonnet{sl.RESET} {sl.GRAY}#1{sl.RESET} | "
        f"{sl.YELLOW}▮▮▮▮▮▮▮▯▯▯ 72% of 200k{sl.RESET} "
        f"{sl.MAGENTA}\u21913.5k{sl.RESET}"
        f" | {sl.GREEN}cache 75%{sl.RESET} | {sl.YELLOW}total $2.35{sl.RESET} "
        f"{sl.RED}\u2191$2.35{sl.RESET}"
    )
    assert out == expected


def test_model_name_newline_is_stripped(tmp_path):
    """Claude Code shows only the FIRST line of stdout. A newline in display_name
    used to leak through and silently truncate the statusline. It's now stripped
    by parse_fields() so the whole line stays intact and single-line."""
    data = {
        "model": {"display_name": "Evil\nModel"},
        "session_id": "s",
        "prompt_id": "p1",
    }
    out = sl.render(data, tmp_path)
    assert "\n" not in out
    assert "EvilModel" in strip_ansi(out)


def test_model_name_ansi_injection_is_stripped(tmp_path):
    """An injected ANSI sequence in display_name must not survive into our output
    (it could recolor or corrupt the terminal). Plain letters may remain; escape
    codes must not."""
    data = {
        "model": {"display_name": "a\033[31mHACK\033[0mb"},
        "session_id": "s",
        "prompt_id": "p1",
    }
    out = sl.render(data, tmp_path)
    # the model segment, once OUR own color codes are stripped, has no leftover ESC
    assert "\033[31m" not in out
    assert "aHACKb" in strip_ansi(out)


def test_non_string_display_name_falls_back(tmp_path):
    data = {"model": {"display_name": ["a", "b"]}, "session_id": "s", "prompt_id": "p1"}
    assert "Claude" in strip_ansi(sl.render(data, tmp_path))


def test_long_display_name_is_truncated(tmp_path):
    data = {"model": {"display_name": "M" * 100}, "session_id": "s", "prompt_id": "p1"}
    out = strip_ansi(sl.render(data, tmp_path))
    # capped at MODEL_NAME_MAX_LEN with an ellipsis, not the full 100 chars
    assert "M" * 100 not in out
    assert "\u2026" in out


@pytest.mark.parametrize("bad_pct", ["9e999", 1e400])
def test_non_finite_percentage_does_not_crash(tmp_path, bad_pct):
    """Regression: used_percentage of inf used to raise OverflowError on int(inf),
    dumping a traceback into the prompt. Must now degrade to 0%."""
    data = {
        "session_id": "s",
        "prompt_id": "p1",
        "context_window": {"used_percentage": bad_pct},
    }
    out = strip_ansi(sl.render(data, tmp_path))
    assert "0%" in out


def test_inf_cost_renders_as_zero(tmp_path):
    data = {"session_id": "s", "prompt_id": "p1", "cost": {"total_cost_usd": 1e400}}
    out = strip_ansi(sl.render(data, tmp_path))
    assert "$inf" not in out
    assert "total $0.00" in out


def test_render_safe_never_raises(tmp_path, monkeypatch):
    """render_safe must swallow any unexpected exception from render and return
    the fallback line instead of propagating a traceback."""
    monkeypatch.setattr(
        sl, "render", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom"))
    )
    assert sl.render_safe({}, tmp_path) == sl.FALLBACK_LINE


def test_atomic_write_leaves_no_temp_files(tmp_path):
    sl.write_cache_file(tmp_path / "statusline-cost-x", "1.23")
    # no leftover .statusline-tmp-* files after a successful write
    assert not list(tmp_path.glob(".statusline-tmp-*"))
    assert (tmp_path / "statusline-cost-x").read_text() == "1.23"


def test_cli_selftest():
    out = strip_ansi(run_cli_args(["--selftest"]))
    assert "Sonnet" in out and "72%" in out


def test_cli_non_dict_json_does_not_crash(tmp_path):
    # top-level JSON array / string / number are valid JSON but not our shape
    for payload in ["[]", '"hi"', "42"]:
        out = strip_ansi(run_cli(payload, tmp_path))
        assert "Claude" in out
