#!/bin/bash
# lib.sh — shared helpers for ctx-protocol scripts.
# Sourced by statusline.sh, hook_router.sh, generate_handoff.sh.
# Every function fails soft (no `set -e`) since callers must never crash a hook.

CTX_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX_ROOT_DIR="$(cd "$CTX_SCRIPTS_DIR/.." && pwd)"
CTX_DATA_DIR="$CTX_ROOT_DIR/data"
CTX_HANDOFFS_DIR="$CTX_DATA_DIR/handoffs"
CTX_SESSIONS_DIR="$CTX_DATA_DIR/sessions"
CTX_ERROR_LOG="$CTX_DATA_DIR/error.log"
CTX_DEFAULT_SETTINGS="$CTX_ROOT_DIR/settings.default.json"
CTX_LOCAL_SETTINGS="$CTX_DATA_DIR/settings.local.json"

mkdir -p "$CTX_HANDOFFS_DIR" "$CTX_SESSIONS_DIR" 2>/dev/null

ctx_log_error() {
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$CTX_ERROR_LOG" 2>/dev/null
}

# Merged effective settings: local overrides win over shipped defaults.
ctx_settings() {
    if [ -f "$CTX_LOCAL_SETTINGS" ]; then
        jq -s '.[0] * .[1]' "$CTX_DEFAULT_SETTINGS" "$CTX_LOCAL_SETTINGS" 2>/dev/null \
            || cat "$CTX_DEFAULT_SETTINGS"
    else
        cat "$CTX_DEFAULT_SETTINGS"
    fi
}

# ctx_setting '.zones.red_pct' 70
# jq's `//` treats JSON `false` as falsy (same as null/missing), which
# would silently discard any boolean setting explicitly set to false — use
# an explicit null-check instead so `false` round-trips correctly.
ctx_setting() {
    local path="$1" default="$2"
    local val
    val=$(ctx_settings | jq -r "(${path}) as \$v | if \$v == null then empty else \$v end" 2>/dev/null)
    [ -n "$val" ] && echo "$val" || echo "$default"
}

ctx_branch() {
    local dir="${1:-$PWD}"
    (cd "$dir" 2>/dev/null && git -c core.useReplaceRefs=false -c gc.auto=0 branch --show-current 2>/dev/null) || echo "no-branch"
}

# Sanitize a branch name into a safe filename stem.
ctx_branch_slug() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

ctx_handoff_path() {
    local branch_slug
    branch_slug=$(ctx_branch_slug "$(ctx_branch "$1")")
    echo "$CTX_HANDOFFS_DIR/${branch_slug}.md"
}

ctx_session_dir() {
    local session_id="$1"
    local d="$CTX_SESSIONS_DIR/${session_id:-unknown}"
    mkdir -p "$d" 2>/dev/null
    echo "$d"
}

# One-shot-per-session marker: returns 0 (true) the first time a given
# notice fires for a session, 1 (false) on every call after.
ctx_notice_once() {
    local session_id="$1" notice="$2"
    local marker_dir
    marker_dir="$(ctx_session_dir "$session_id")/notices"
    mkdir -p "$marker_dir" 2>/dev/null
    local marker="$marker_dir/$notice"
    if [ -f "$marker" ]; then
        return 1
    fi
    touch "$marker" 2>/dev/null
    return 0
}

# Delete session directories older than log.retention_days (settings-driven).
ctx_prune_old_sessions() {
    local days
    days=$(ctx_setting '.log.retention_days' 30)
    find "$CTX_SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+${days}" -exec rm -rf {} \; 2>/dev/null
}

# Zone for a given percentage: prints "green" | "yellow" | "red"
ctx_zone() {
    local pct="$1"
    local yellow red
    yellow=$(ctx_setting '.zones.yellow_pct' 50)
    red=$(ctx_setting '.zones.red_pct' 70)
    if awk -v p="$pct" -v r="$red" 'BEGIN{exit !(p>=r)}'; then
        echo "red"
    elif awk -v p="$pct" -v y="$yellow" 'BEGIN{exit !(p>=y)}'; then
        echo "yellow"
    else
        echo "green"
    fi
}
