#!/usr/bin/env python3
"""
claude_router.py — a lightweight REPL wrapper around `claude -p` that
classifies each prompt and automatically picks the model to run it on,
threading conversation state across turns via --resume.

Usage:
    python3 claude_router.py

Force a specific model for one turn:
    use opus: refactor this whole module for scalability
    use haiku: what does this regex do
"""

from __future__ import annotations

import json
import re
import subprocess
import sys

# ---- classification rules (tune these to taste) ----------------------

COMPLEX_KEYWORDS = re.compile(
    r"\b(architect\w*|refactor\w*|redesign\w*|migrat\w*|trade-?off\w*|"
    r"security review|scalab\w*|debug deeply|root cause|design a)\b",
    re.IGNORECASE,
)

SIMPLE_KEYWORDS = re.compile(
    r"\b(rename\w*|typo|format\w*|list\b|what is|explain briefly|quick\w*|"
    r"one[- ]liner|lookup|grep)\b",
    re.IGNORECASE,
)

FORCE_PREFIX = re.compile(r"^\s*use[: ]+(opus|sonnet|haiku)\s*[:,-]?\s*", re.IGNORECASE)

WORD_COUNT_OPUS_THRESHOLD = 120
WORD_COUNT_HAIKU_THRESHOLD = 12


def classify(prompt: str) -> str:
    """Return 'opus' | 'sonnet' | 'haiku' for a given prompt."""
    forced = FORCE_PREFIX.match(prompt)
    if forced:
        return forced.group(1).lower()

    word_count = len(prompt.split())

    if COMPLEX_KEYWORDS.search(prompt) or word_count > WORD_COUNT_OPUS_THRESHOLD:
        return "opus"
    if SIMPLE_KEYWORDS.search(prompt) or word_count < WORD_COUNT_HAIKU_THRESHOLD:
        return "haiku"
    return "sonnet"


def strip_force_prefix(prompt: str) -> str:
    return FORCE_PREFIX.sub("", prompt, count=1)


# ---- talking to claude -------------------------------------------------

def run_claude(prompt: str, model: str, session_id: str | None) -> dict:
    cmd = ["claude", "-p", prompt, "--model", model, "--output-format", "json"]
    if session_id:
        cmd += ["--resume", session_id]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"[error] claude exited {result.returncode}: {result.stderr.strip()}",
              file=sys.stderr)
        sys.exit(result.returncode)

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        # Fall back to raw text if something upstream didn't return JSON
        print(result.stdout)
        sys.exit(1)


# ---- main loop ----------------------------------------------------------

def main() -> None:
    session_id = None
    print("Claude model-switching wrapper. Ctrl+D to exit.")
    print("Prefix a message with 'use opus:' / 'use sonnet:' / 'use haiku:' "
          "to force a model for that turn.\n")

    while True:
        try:
            prompt = input("you> ").strip()
        except EOFError:
            print("\nbye")
            break

        if not prompt:
            continue

        model = classify(prompt)
        clean_prompt = strip_force_prefix(prompt)

        print(f"[routing -> {model}]")
        data = run_claude(clean_prompt, model, session_id)

        session_id = data.get("session_id", session_id)
        cost = data.get("total_cost_usd")
        actual_model = next(iter(data.get("modelUsage", {})), model)

        print(f"\nclaude ({actual_model})> {data.get('result', '')}\n")
        if cost is not None:
            print(f"[cost this turn: ${cost:.4f}]\n")


if __name__ == "__main__":
    main()