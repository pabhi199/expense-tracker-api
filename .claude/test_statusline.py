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
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import statusline as sl  # noqa: E402

SCRIPT = Path(__file__).parent / "statusline.py"


# ---------------------------------------------------------------------------
# Tier 1: unit tests on pure functions (no subprocess at all)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("value,expected", [
    (60, True), (60.5, True), ("60", True), ("60.5", True),
    ("oops", False), (None, False), ("", False), (True, False),
])
def test_is_num(value, expected):
    assert sl.is_num(value) is expected


@pytest.mark.parametrize("pct,expected_pct", [(150, 100), (-20, 0), (72, 72)])
def test_pct_clamping_via_render(pct, expected_pct, tmp_path):
    data = {"session_id": "s", "prompt_id": "p", "context_window": {"used_percentage": pct}}
    out = sl.render(data, tmp_path)
    assert f"{expected_pct}%" in out


@pytest.mark.parametrize("pct,expected_color", [
    (59, sl.CTX_COLOR_OK), (60, sl.CTX_COLOR_WARN), (84, sl.CTX_COLOR_WARN), (85, sl.CTX_COLOR_CRIT),
])
def test_context_bar_color_thresholds(pct, expected_color):
    _, color = sl.compute_context_bar(pct)
    assert color == expected_color


@pytest.mark.parametrize("pct", [95, 99, 100])
def test_context_bar_rounds_to_full(pct):
    bar, _ = sl.compute_context_bar(pct)
    assert bar == "▮" * 10


@pytest.mark.parametrize("size,expected", [(200_000, "200k"), (1_500_000, "1M"), (500, "500"), (0, ""), (None, "")])
def test_human_size(size, expected):
    assert sl.human_size(size) == expected


@pytest.mark.parametrize("out_tok,in_tok,cache_create,expected_str,expected_color", [
    (50, 100, 0, "+150", sl.TOKEN_COLOR_LOW),
    (0, 999, 0, "+999", sl.TOKEN_COLOR_LOW),          # just under the k-format threshold
    (0, 1999, 0, "\u21912.0k", sl.TOKEN_COLOR_LOW),     # k-format, but still gray (color threshold is 2000)
    (0, 2000, 0, "\u21912.0k", sl.TOKEN_COLOR_MID),
    (0, 8000, 0, "\u21918.0k", sl.TOKEN_COLOR_HIGH),
    (0, 0, 0, "", sl.TOKEN_COLOR_LOW),
])
def test_compute_token_delta(out_tok, in_tok, cache_create, expected_str, expected_color):
    growth, delta_str, color = sl.compute_token_delta(out_tok, in_tok, cache_create)
    assert delta_str == expected_str
    assert color == expected_color


def test_cache_read_excluded_from_growth():
    growth, delta_str, _ = sl.compute_token_delta(out_tok=0, in_tok=100, cache_create=0)
    # cache_read isn't even a parameter here by design -- growth must ignore it entirely
    assert growth == 100
    assert delta_str == "+100"


@pytest.mark.parametrize("cache_read,in_tok,cache_create,expected", [
    (0, 0, 0, None),
    (50, 50, 0, 50),
    (75, 25, 0, 75),
])
def test_compute_cache_pct(cache_read, in_tok, cache_create, expected):
    assert sl.compute_cache_pct(cache_read, in_tok, cache_create) == expected


@pytest.mark.parametrize("cost,expected", [(0.50, sl.TOTAL_COST_COLOR_OK), (1.00, sl.TOTAL_COST_COLOR_WARN), (5.00, sl.TOTAL_COST_COLOR_CRIT)])
def test_total_cost_color(cost, expected):
    assert sl.total_cost_color(cost) == expected


@pytest.mark.parametrize("cost,expected", [(0.01, sl.TURN_COST_COLOR_OK), (0.05, sl.TURN_COST_COLOR_WARN), (0.25, sl.TURN_COST_COLOR_CRIT)])
def test_turn_cost_color(cost, expected):
    assert sl.turn_cost_color(cost) == expected


@pytest.mark.parametrize("raw,expected", [
    ("abc/../def", "abcdef"), ("safe-id_123", "safe-id_123"), ("", "nosession"), (None, "nosession"),
])
def test_clean_session_id(raw, expected):
    assert sl.clean_session_id(raw) == expected


# ---------------------------------------------------------------------------
# Tier 1b: render() with an in-memory tmp_path -- still no subprocess, but
# exercises the full assembly + stateful cache-file logic together.
# ---------------------------------------------------------------------------

def test_null_current_usage_does_not_crash(tmp_path):
    data = {"model": {"display_name": "Sonnet"}, "session_id": "s2", "prompt_id": "p1",
            "context_window": {"used_percentage": 10, "current_usage": None},
            "cost": {"total_cost_usd": 0}}
    assert "Sonnet" in sl.render(data, tmp_path)


def test_missing_context_window(tmp_path):
    data = {"model": {"display_name": "X"}, "session_id": "s3", "prompt_id": "p1"}
    assert "0%" in sl.render(data, tmp_path)


def test_non_numeric_used_percentage(tmp_path):
    data = {"session_id": "s4", "prompt_id": "p1", "context_window": {"used_percentage": "oops"}}
    assert "0%" in sl.render(data, tmp_path)


def test_non_numeric_cost(tmp_path):
    data = {"session_id": "s5", "prompt_id": "p1", "cost": {"total_cost_usd": "NaN"}}
    assert "total $0.00" in sl.render(data, tmp_path)


def test_turn_cost_delta_across_calls(tmp_path):
    sl.render({"session_id": "st1", "prompt_id": "p1", "cost": {"total_cost_usd": 1.00}}, tmp_path)
    out = sl.render({"session_id": "st1", "prompt_id": "p2", "cost": {"total_cost_usd": 1.30}}, tmp_path)
    assert "\u2191$0.30" in out


def test_turn_cost_never_negative_after_reset(tmp_path):
    sl.render({"session_id": "st2", "prompt_id": "p1", "cost": {"total_cost_usd": 3.00}}, tmp_path)
    out = sl.render({"session_id": "st2", "prompt_id": "p2", "cost": {"total_cost_usd": 0}}, tmp_path)
    assert "\u2191$-" not in out


def test_prompt_counter_dedupes_and_increments(tmp_path):
    o1 = sl.render({"session_id": "st3", "prompt_id": "pA"}, tmp_path)
    o2 = sl.render({"session_id": "st3", "prompt_id": "pA"}, tmp_path)  # repeat, no bump
    o3 = sl.render({"session_id": "st3", "prompt_id": "pB"}, tmp_path)  # new, bumps
    assert "#1" in o1 and "#1" in o2 and "#2" in o3


def test_readonly_cache_dir_does_not_crash(tmp_path):
    ro = tmp_path / "ro"
    ro.mkdir()
    ro.chmod(0o555)
    try:
        out = sl.render({"session_id": "ro1", "prompt_id": "p1", "cost": {"total_cost_usd": 2.00}}, ro)
        assert "total $2.00" in out
    finally:
        ro.chmod(0o755)


# ---------------------------------------------------------------------------
# Tier 2: integration tests through the real CLI (stdin -> stdout)
# ---------------------------------------------------------------------------

def run_cli(payload, tmp_path) -> str:
    stdin_data = payload if isinstance(payload, str) else json.dumps(payload)
    import os
    env = os.environ.copy()
    env["TMPDIR"] = str(tmp_path)
    result = subprocess.run([sys.executable, str(SCRIPT)], input=stdin_data,
                             capture_output=True, text=True, env=env, timeout=10)
    return result.stdout + result.stderr


def test_cli_empty_input(tmp_path):
    assert "waiting for session data" in run_cli("", tmp_path)


def test_cli_malformed_json(tmp_path):
    assert "waiting for session data" in run_cli("{not valid json", tmp_path)


def test_cli_full_roundtrip(tmp_path):
    payload = {"model": {"display_name": "Sonnet"}, "session_id": "cli1", "prompt_id": "p1",
               "context_window": {"used_percentage": 42}, "cost": {"total_cost_usd": 0.10}}
    out = run_cli(payload, tmp_path)
    assert "Sonnet" in out and "42%" in out and "total $0.10" in out
