#!/bin/bash
# statusline.sh — ctx-tool's context-window statusline.
# Reads the statusLine JSON contract on stdin (context_window, cost, model,
# session_id, transcript_path — see Claude Code statusline docs) and renders
# one color-coded line. Never blocks and never errors out loud: any failure
# degrades to a minimal line rather than a blank statusline.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh" 2>/dev/null || exit 0

input=$(cat)

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000' 2>/dev/null)
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)
session_id=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
model_name=$(echo "$input" | jq -r '.model.display_name // "?"' 2>/dev/null)

used_int=$(printf '%.0f' "${used_pct:-0}" 2>/dev/null || echo 0)
zone=$(ctx_zone "$used_int")

case "$zone" in
    red)    color="\033[31m" ;;
    yellow) color="\033[33m" ;;
    *)      color="\033[32m" ;;
esac
reset="\033[0m"

# --- bar ---
bar_len=8
filled=$((used_int * bar_len / 100))
[ "$filled" -gt "$bar_len" ] && filled=$bar_len
empty=$((bar_len - filled))
bar=""
for ((i = 0; i < filled; i++)); do bar+="▮"; done
for ((i = 0; i < empty; i++)); do bar+="▯"; done

# --- burn rate + forecast, from this session's turn log ---
# Average successive context_tokens deltas over the last few turns, then
# project how many turns remain until auto_compact_pct at that burn rate.
turns_file="$(ctx_session_dir "$session_id")/turns.jsonl"
turns_left="–"
tok_per_turn="–"
spike=0
if [ -f "$turns_file" ]; then
    # Only real per-turn records carry context_tokens (compaction-event rows
    # logged separately don't), so filter those out before diffing.
    deltas=$(tail -n 20 "$turns_file" 2>/dev/null | jq -r 'select(has("context_tokens")) | .context_tokens' 2>/dev/null | tail -n 6)
    if [ -n "$deltas" ]; then
        read -r avg last_delta spike <<< "$(echo "$deltas" | awk 'NF{a[NR]=$1} END{
            if (NR<2) { print "0 0 0"; exit }
            s=0; c=0
            for (i=2;i<=NR;i++){ d=a[i]-a[i-1]; if (d>0){ s+=d; c++ } }
            if (c==0) { print "0 0 0"; exit }
            avg=s/c
            last=a[NR]-a[NR-1]
            spiked=(c>=2 && last > avg*2) ? 1 : 0
            printf "%.0f %.0f %d", avg, last, spiked
        }')"
        if [ -n "${avg:-}" ] && [ "$avg" -gt 0 ] 2>/dev/null; then
            if [ "$avg" -ge 1000 ]; then
                tok_per_turn="$(awk -v a="$avg" 'BEGIN{printf "%.1fk", a/1000}')"
            else
                tok_per_turn="${avg}"
            fi
            compact_pct=$(ctx_setting '.statusline.auto_compact_pct' 92)
            remaining_tokens=$(awk -v u="$used_int" -v c="$compact_pct" -v s="$context_size" 'BEGIN{
                r=(c-u)/100*s; if (r<0) r=0; printf "%.0f", r
            }')
            tl=$(awk -v r="$remaining_tokens" -v a="$avg" 'BEGIN{ printf "%.0f", r/a }')
            turns_left="$tl"
        fi
    fi
fi

# --- cost ---
cost_str=""
show_cost=$(ctx_setting '.statusline.show_cost' true)
if [ "$show_cost" = "true" ] && [ -n "${cost_usd:-}" ] && [ "$cost_usd" != "null" ]; then
    cost_str=$(awk -v c="$cost_usd" 'BEGIN{printf "$%.2f", c}')
fi

# --- assemble ---
# Zone is conveyed by the bar's color alone — no redundant text label.
parts=("${color}${bar}${reset} ${used_int}%")
show_burn=$(ctx_setting '.statusline.show_burn_rate' true)
if [ "$show_burn" = "true" ]; then
    [ "$turns_left" != "–" ] && parts+=("≈${turns_left} turns")
    if [ "$tok_per_turn" != "–" ]; then
        if [ "${spike:-0}" = "1" ]; then
            parts+=("\033[35m${tok_per_turn} tok/turn ⚡\033[0m")
        else
            parts+=("${tok_per_turn} tok/turn")
        fi
    fi
fi
[ -n "$cost_str" ] && parts+=("${cost_str}")

result="[${model_name}]"
for p in "${parts[@]}"; do
    result="${result} | ${p}"
done

printf '%b\n' "$result"
