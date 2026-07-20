#!/bin/bash
# ctx.sh <subcommand> [args...] — single entrypoint for everything
# ctx-protocol does outside the statusline (which has its own stdin-JSON
# contract and stays in statusline.sh). Subcommands:
#   hook <event>                  hook dispatch (SessionStart/Stop/PreCompact/
#                                  PostCompact/SessionEnd), reads hook JSON on stdin
#   handoff <sid> <transcript> <cwd> <reason>   write a durable handoff.md
#   print-handoff-info [dir]      branch/path/keep_backup, for the handoff skill
#   print-handoff-content [dir]   saved handoff or fallback, for resume-handoff
#   print-settings                 effective merged settings, for ctx-settings
set -u

# `handoff` shells out to `claude -p` from inside this same project dir, so
# that nested session inherits settings.json and would otherwise re-trigger
# `ctx.sh hook ...` itself (SessionEnd -> handoff -> claude -p -> SessionEnd
# -> ...). Bail immediately when we're that nested call.
[ -n "${CTX_PROTOCOL_SUPPRESS_HOOKS:-}" ] && exit 0

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh" 2>/dev/null || exit 0

subcommand="${1:-}"
[ $# -gt 0 ] && shift

cmd_handoff() {
    local session_id="${1:-unknown}" transcript_path="${2:-}" cwd="${3:-$PWD}" reason="${4:-manual}"

    [ -f "$transcript_path" ] || { ctx_log_error "handoff: no transcript at $transcript_path"; return 0; }
    command -v claude >/dev/null 2>&1 || { ctx_log_error "handoff: claude CLI not on PATH"; return 0; }

    local branch handoff_path tail_lines model max_tokens condensed prompt result_json body keep_backup store_in_repo
    branch=$(ctx_branch "$cwd")
    handoff_path=$(ctx_handoff_path "$cwd")
    tail_lines=$(ctx_setting '.handoff.transcript_tail_lines' 400)
    model=$(ctx_setting '.handoff.model' haiku)
    max_tokens=$(ctx_setting '.handoff.max_summary_tokens' 800)

    condensed=$(tail -n "$tail_lines" "$transcript_path" 2>/dev/null | jq -rs '
        [.[] | select(.type=="user" or .type=="assistant")
         | . as $m
         | (if ($m.message.content | type) == "string" then $m.message.content
            else
              ($m.message.content // [] | map(
                 if .type=="text" then .text
                 elif .type=="tool_use" then "[tool:" + .name + "]"
                 else empty end
               ) | join(" "))
            end) as $txt
         | select($txt != "")
         | $m.type + ": " + $txt
        ] | join("\n")
    ' 2>/dev/null)

    [ -z "$condensed" ] && { ctx_log_error "handoff: nothing to summarize"; return 0; }

    prompt=$(cat << EOF
Write a compact session handoff for future-you to resume this work later.
Output ONLY the following structure, no preamble, no markdown code fences:

Summary: <one line, under 100 chars, current state of the task>

## What I was doing
<2-4 short bullets>

## Decisions made
<bullets, or "None recorded.">

## Unresolved items
<bullets, or "None.">

## Files touched
<bullet list of file paths seen in the transcript, or "None identified.">

Keep the entire output under ${max_tokens} tokens. Transcript excerpt:
---
${condensed}
---
EOF
)

    result_json=$(CTX_PROTOCOL_SUPPRESS_HOOKS=1 claude -p "$prompt" --model "$model" --output-format json 2>>"$CTX_ERROR_LOG")
    body=$(echo "$result_json" | jq -r '.result // empty' 2>/dev/null)
    [ -z "$body" ] && { ctx_log_error "handoff: empty model output for $reason"; return 0; }

    keep_backup=$(ctx_setting '.handoff.keep_backup' true)
    if [ "$keep_backup" = "true" ] && [ -f "$handoff_path" ]; then
        cp "$handoff_path" "${handoff_path}.1" 2>/dev/null
    fi

    {
        echo "# Handoff — ${branch}"
        echo "_Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC · reason: ${reason} · session ${session_id:0:8}_"
        echo
        echo "$body"
    } > "$handoff_path" 2>/dev/null

    store_in_repo=$(ctx_setting '.handoff.store_in_repo' false)
    if [ "$store_in_repo" = "true" ]; then
        git -C "$cwd" add -f "$handoff_path" 2>/dev/null
    fi
}

# Rough context-fullness estimate, used only in-memory to decide whether
# this turn crosses into the red zone. Hook payloads don't carry the real
# context_window_size (only statusLine gets that), so this assumes a 200k
# window — it can read low for sessions on a larger one. Precise enough to
# trigger the "you're probably getting full" insurance write, NOT precise
# enough to persist as fact, so it never gets written to turns.jsonl.
# Prints: used_pct tokens_in tokens_out cache_creation cache_read
ctx_estimate_usage() {
    [ -f "$transcript_path" ] || { echo "0 0 0 0 0"; return; }
    local usage window=200000
    usage=$(tail -n 60 "$transcript_path" 2>/dev/null | jq -rs '
        [.[] | select(.type=="assistant") | .message.usage] | last // empty' 2>/dev/null)
    [ -z "$usage" ] || [ "$usage" = "null" ] && { echo "0 0 0 0 0"; return; }
    echo "$usage" | jq -r --argjson w "$window" '
        (.input_tokens // 0) as $in | (.output_tokens // 0) as $out |
        (.cache_creation_input_tokens // 0) as $cc | (.cache_read_input_tokens // 0) as $cr |
        ((($in + $cc + $cr)/$w)*100 | floor) as $pct |
        "\($pct) \($in) \($out) \($cc) \($cr)"
    ' 2>/dev/null || echo "0 0 0 0 0"
}

# Tool calls + files touched since the last Stop, via a per-session line
# marker (avoids re-scanning the whole transcript every turn). File paths
# are relativized to $cwd — logging them absolute is just noise.
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
    echo "$new_lines" | jq -rs --arg cwd "$cwd" '{
        tools: ([.[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name] | unique),
        files: ([.[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | (.input.file_path // empty)] | unique | map(ltrimstr($cwd + "/")))
    }' 2>/dev/null || echo '{"tools":[],"files":[]}'
}

cmd_hook() {
    local event="${1:-}"
    local input session_id transcript_path cwd
    input=$(cat)
    session_id=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
    transcript_path=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
    cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
    [ -z "$cwd" ] && cwd="$PWD"

    case "$event" in

    session_start)
        ctx_prune_old_sessions
        local handoff_path on_start summary branch age_min age_str msg auto_inject
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
        local tf pct tokens_in tokens_out cache_creation cache_read zone model activity on_red
        tf="$(ctx_session_dir "$session_id")/turns.jsonl"
        read -r pct tokens_in tokens_out cache_creation cache_read <<< "$(ctx_estimate_usage)"
        zone=$(ctx_zone "$pct")
        model=$(tail -n 30 "$transcript_path" 2>/dev/null | jq -rs '[.[] | select(.type=="assistant") | .message.model // empty] | last // "unknown"' 2>/dev/null)
        activity=$(ctx_turn_activity)

        # context_tokens/used_pct/zone/cost aren't logged: the first three
        # are derivable from tokens_in+cache_creation+cache_read (or
        # unreliable, in used_pct/zone's case — see ctx_estimate_usage), and
        # cost is never available to hooks at all, only to the statusline.
        jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg session "${session_id:0:8}" \
            --arg model "$model" \
            --argjson tokens_in "${tokens_in:-0}" --argjson tokens_out "${tokens_out:-0}" \
            --argjson cache_creation "${cache_creation:-0}" --argjson cache_read "${cache_read:-0}" \
            --argjson activity "$activity" \
            '{ts:$ts, session:$session, model:$model,
              tokens_in:$tokens_in, tokens_out:$tokens_out, cache_creation:$cache_creation, cache_read:$cache_read,
              tools:$activity.tools, files:$activity.files}' \
            >> "$tf" 2>/dev/null

        on_red=$(ctx_setting '.notices.on_red' true)
        if [ "$zone" = "red" ] && [ "$on_red" = "true" ] && ctx_notice_once "$session_id" "red"; then
            # Insurance before advice (design principle #3): write the handoff
            # synchronously and only emit the notice once it has landed.
            cmd_handoff "$session_id" "$transcript_path" "$cwd" "red_zone" 2>>"$CTX_ERROR_LOG"
            jq -n '{systemMessage: "⚠ context is getting full — handoff saved. /compact or /clear recommended."}'
        fi
        ;;

    pre_compact)
        # Insurance before advice: write the handoff synchronously so it lands
        # before compaction, unconditionally (not gated by notices settings).
        cmd_handoff "$session_id" "$transcript_path" "$cwd" "pre_compact" 2>>"$CTX_ERROR_LOG"
        jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg session "${session_id:0:8}" \
            '{ts:$ts, session:$session, event:"pre_compact"}' >> "$(ctx_session_dir "$session_id")/turns.jsonl" 2>/dev/null
        ;;

    post_compact)
        jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg session "${session_id:0:8}" \
            '{ts:$ts, session:$session, event:"post_compact"}' >> "$(ctx_session_dir "$session_id")/turns.jsonl" 2>/dev/null
        local on_post auto_inject handoff_path
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
        cmd_handoff "$session_id" "$transcript_path" "$cwd" "session_end" 2>>"$CTX_ERROR_LOG"
        ;;

    esac
}

case "$subcommand" in
    hook)
        cmd_hook "$@"
        ;;
    handoff)
        cmd_handoff "$@"
        ;;
    print-handoff-info)
        dir="${1:-$PWD}"
        echo "branch: $(ctx_branch "$dir")"
        echo "path: $(ctx_handoff_path "$dir")"
        echo "keep_backup: $(ctx_setting '.handoff.keep_backup' true)"
        ;;
    print-handoff-content)
        dir="${1:-$PWD}"
        p=$(ctx_handoff_path "$dir")
        if [ -f "$p" ]; then
            cat "$p"
        else
            echo "No handoff found for this project/branch yet. Run /handoff to create one."
        fi
        ;;
    print-settings)
        ctx_settings
        ;;
esac

exit 0
