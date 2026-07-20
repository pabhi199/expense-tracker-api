#!/bin/bash
# claude-auto: Simple wrapper for your existing 'claude' CLI
# Works with whatever 'claude' command you already have installed

set -euo pipefail

PROMPT="${*:-}"
DEBUG="${DEBUG:-0}"

# Analyze prompt complexity
analyze() {
    local text="$1"
    local lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')
    local length=${#text}
    
    # Haiku if very short (less than 10 chars)
    if [[ $length -lt 10 ]]; then
        echo "haiku"
    # Opus (complex)
    elif echo "$lower" | grep -qiE 'architect|security|distributed|scalab|performance|multi.*service'; then
        echo "opus"
    # Haiku (simple keywords)
    elif echo "$lower" | grep -qiE 'typo|simple|boilerplate|fix.*bug|rename|README'; then
        echo "haiku"
    # Sonnet (default)
    else
        echo "sonnet"
    fi
}

# Validate input
if [[ -z "$PROMPT" ]]; then
    echo "Usage: $(basename "$0") 'your prompt'" >&2
    exit 1
fi

# Check if claude command exists
if ! command -v claude &> /dev/null; then
    echo "ERROR: 'claude' command not found" >&2
    echo "Make sure Claude CLI is installed and in your PATH" >&2
    exit 1
fi

# Determine model
MODEL=$(analyze "$PROMPT")

if [[ "$DEBUG" == "1" ]]; then
    echo "[claude-auto] Prompt: ${PROMPT:0:60}..." >&2
    echo "[claude-auto] Model: $MODEL" >&2
fi

# Try to pass model flag (may not work depending on your claude CLI version)
if claude --help 2>/dev/null | grep -q "model"; then
    # Claude CLI supports --model flag
    exec claude --model "$MODEL" "$PROMPT"
else
    # Claude CLI doesn't support --model, just use default
    if [[ "$DEBUG" == "1" ]]; then
        echo "[claude-auto] WARNING: claude CLI doesn't support --model flag" >&2
        echo "[claude-auto] Using default model instead" >&2
    fi
    exec claude "$PROMPT"
fi