#!/bin/bash
# hook_router.sh <event> — single entrypoint wired into settings.json for
# SessionStart / Stop / PreCompact / PostCompact / SessionEnd. Reads the
# hook JSON payload on stdin, dispatches on $1, and (per design principle
# #4 in the readme) never lets an internal failure interrupt the session:
# every branch falls through to `exit 0`.
set -u

# generate_handoff.sh shells out to `claude -p` from inside this same
# project dir, so that nested session inherits settings.json and would
# otherwise re-trigger these very hooks (SessionEnd -> generate_handoff.sh
# -> claude -p -> SessionEnd -> ...). Bail immediately when we're that
# nested call.
[ -n "${CTX_PROTOCOL_SUPPRESS_HOOKS:-}" ] && exit 0

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh" 2>/dev/null || exit 0

event="${1:-}"
input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

GENERATE_HANDOFF="$CTX_SCRIPTS_DIR/generate_handoff.sh"

# Hook payloads don't carry context_window/cost (those are statusLine-only
# fields) — approximate context size from the last assistant message's
# usage block in the transcript instead. This is the same number the
# statusline bar is built from, just recomputed independently here.
# Prints: context_tokens used_pct tokens_in tokens_out cache_creation cache_read
ctx_estimate_usage() {
    [ -f "$transcript_path" ] || { echo "0 0 0 0 0 0"; return; }
    local usage window=200000
    usage=$(tail -n 60 "$transcript_path" 2>/dev/null | jq -rs '
        [.[] | select(.type=="assistant") | .message.usage] | last // empty' 2>/dev/null)
    [ -z "$usage" ] || [ "$usage" = "null" ] && { echo "0 0 0 0 0 0"; return; }
    echo "$usage" | jq -r --argjson w "$window" '
        (.input_tokens // 0) as $in | (.output_tokens // 0) as $out |
        (.cache_creation_input_tokens // 0) as $cc | (.cache_read_input_tokens // 0) as $cr |
        (($in + $cc + $cr)) as $total |
        "\($total) \((($total/$w)*100)|floor) \($in) \($out) \($cc) \($cr)"
    ' 2>/dev/null || echo "0 0 0 0 0 0"
}

# Tool calls + files touched since the last Stop, via a per-session line
# marker (avoids re-scanning the whole transcript every turn).
ctx_turn_activity() {
    local marker="$(ctx_session_dir "$session_id")/last_stop_line"
    local prev=0 total new_lines
    [ -f "$marker" ] && prev=$(cat "$marker" 2>/dev/null || echo 0)
    total=$(wc -l < "$transcript_path" 2>/dev/null | tr -d ' ')
    total="${total:-0}"
    new_lines=$(tail -n "+$((prev + 1))" "$transcript_path" 2>/dev/null)
    echo "$total" > "$marker" 2>/dev/null
    if [ -z "$new_lines" ]; then
        echo '{"tools":[],"files":[]}'
        return
    fi
    echo "$new_lines" | jq -rs '{
        tools: ([.[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name] | unique),
        files: ([.[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | (.input.file_path // empty)] | unique)
    }' 2>/dev/null || echo '{"tools":[],"files":[]}'
}

case "$event" in

session_start)
    ctx_prune_old_sessions
    handoff_path=$(ctx_handoff_path "$cwd")
    on_start=$(ctx_setting '.notices.on_session_start' true)
    if [ "$on_start" = "true" ] && [ -f "$handoff_path" ] && ctx_notice_once "$session_id" "session_start"; then
        summary=$(grep -m1 '^Summary:' "$handoff_path" 2>/dev/null | sed 's/^Summary: *//')
        [ -z "$summary" ] && summary="(no summary line found)"
        branch=$(ctx_branch "$cwd")
        age_min=$(( ( $(date -u +%s) - $(stat -f %m "$handoff_path" 2>/dev/null || stat -c %Y "$handoff_path" 2>/dev/null || echo 0) ) / 60 ))
        age_str="${age_min}m old"
        [ "$age_min" -ge 60 ] && age_str="$((age_min / 60))h old"
        msg="Handoff for ${branch} (${age_str}): \"${summary}\" — /resume-handoff to load."

        auto_inject=$(ctx_setting '.auto_inject.session_start' false)
        if [ "$auto_inject" = "true" ]; then
            jq -n --arg msg "$msg" --arg ctx "$(cat "$handoff_path")" \
                '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
        else
            jq -n --arg msg "$msg" '{systemMessage: $msg}'
        fi
    fi
    ;;

stop)
    tf="$(ctx_session_dir "$session_id")/turns.jsonl"
    read -r tokens pct tokens_in tokens_out cache_creation cache_read <<< "$(ctx_estimate_usage)"
    zone=$(ctx_zone "$pct")
    model=$(tail -n 30 "$transcript_path" 2>/dev/null | jq -rs '[.[] | select(.type=="assistant") | .message.model // empty] | last // "unknown"' 2>/dev/null)
    activity=$(ctx_turn_activity)

    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg session "${session_id:0:8}" \
        --arg model "$model" --argjson tokens "${tokens:-0}" --argjson pct "${pct:-0}" --arg zone "$zone" \
        --argjson tokens_in "${tokens_in:-0}" --argjson tokens_out "${tokens_out:-0}" \
        --argjson cache_creation "${cache_creation:-0}" --argjson cache_read "${cache_read:-0}" \
        --argjson activity "$activity" \
        '{ts:$ts, session:$session, model:$model, context_tokens:$tokens, used_pct:$pct, zone:$zone,
          tokens_in:$tokens_in, tokens_out:$tokens_out, cache_creation:$cache_creation, cache_read:$cache_read,
          tools:$activity.tools, files:$activity.files, cost_usd:null}' \
        >> "$tf" 2>/dev/null

    on_red=$(ctx_setting '.notices.on_red' true)
    if [ "$zone" = "red" ] && [ "$on_red" = "true" ] && ctx_notice_once "$session_id" "red"; then
        # Insurance before advice (design principle #3): write the handoff
        # synchronously and only emit the notice once it has landed.
        bash "$GENERATE_HANDOFF" "$session_id" "$transcript_path" "$cwd" "red_zone" >/dev/null 2>>"$CTX_ERROR_LOG"
        jq -n --argjson pct "$pct" '{systemMessage: ("⚠ " + ($pct|tostring) + "% — handoff saved. /compact or /clear recommended.")}'
    fi
    ;;

pre_compact)
    # Insurance before advice: write the handoff synchronously so it lands
    # before compaction, unconditionally (not gated by notices settings).
    bash "$GENERATE_HANDOFF" "$session_id" "$transcript_path" "$cwd" "pre_compact" >/dev/null 2>>"$CTX_ERROR_LOG"
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg session "${session_id:0:8}" \
        '{ts:$ts, session:$session, event:"pre_compact"}' >> "$(ctx_session_dir "$session_id")/turns.jsonl" 2>/dev/null
    ;;

post_compact)
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg session "${session_id:0:8}" \
        '{ts:$ts, session:$session, event:"post_compact"}' >> "$(ctx_session_dir "$session_id")/turns.jsonl" 2>/dev/null
    on_post=$(ctx_setting '.notices.on_post_compact' true)
    if [ "$on_post" = "true" ] && ctx_notice_once "$session_id" "post_compact"; then
        auto_inject=$(ctx_setting '.auto_inject.post_compact' false)
        if [ "$auto_inject" = "true" ]; then
            handoff_path=$(ctx_handoff_path "$cwd")
            if [ -f "$handoff_path" ]; then
                jq -n --arg ctx "$(cat "$handoff_path")" \
                    '{systemMessage: "Compacted. Handoff restored.", hookSpecificOutput: {hookEventName: "PostCompact", additionalContext: $ctx}}'
            fi
        else
            jq -n '{systemMessage: "Compacted. /resume-handoff to restore task state."}'
        fi
    fi
    ;;

session_end)
    bash "$GENERATE_HANDOFF" "$session_id" "$transcript_path" "$cwd" "session_end" >/dev/null 2>>"$CTX_ERROR_LOG"
    ;;

esac

exit 0
