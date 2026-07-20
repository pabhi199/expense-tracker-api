#!/bin/bash
# generate_handoff.sh <session_id> <transcript_path> <cwd> <reason>
# Writes a durable handoff.md for the current project+branch by asking a
# (cheap, haiku-by-default) model to condense the recent transcript into a
# short structured summary. Always called synchronously — design principle
# #3 requires the snapshot to land *before* the notice that references it,
# for every trigger (red zone, pre-compact, session end).
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh" 2>/dev/null || exit 0

session_id="${1:-unknown}"
transcript_path="${2:-}"
cwd="${3:-$PWD}"
reason="${4:-manual}"

[ -f "$transcript_path" ] || { ctx_log_error "generate_handoff: no transcript at $transcript_path"; exit 0; }
command -v claude >/dev/null 2>&1 || { ctx_log_error "generate_handoff: claude CLI not on PATH"; exit 0; }

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

[ -z "$condensed" ] && { ctx_log_error "generate_handoff: nothing to summarize"; exit 0; }

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
[ -z "$body" ] && { ctx_log_error "generate_handoff: empty model output for $reason"; exit 0; }

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

exit 0
