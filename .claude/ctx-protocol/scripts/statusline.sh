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
default_window=$(ctx_setting '.zones.assumed_context_window' 200000)
context_size=$(echo "$input" | jq -r --argjson d "$default_window" '.context_window.context_window_size // $d' 2>/dev/null)
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty' 2>/dev/null)
session_id=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
model_name=$(echo "$input" | jq -r '.model.display_name // "?"' 2>/dev/null)
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)

# window size, human-readable (200000 -> "200K", 1000000 -> "1M")
if [ "$context_size" -ge 1000000 ] 2>/dev/null; then
    window_str="$(awk -v s="$context_size" 'BEGIN{v=s/1000000; printf (v==int(v))?"%dM":"%.1fM", v}')"
elif [ "$context_size" -ge 1000 ] 2>/dev/null; then
    window_str="$(awk -v s="$context_size" 'BEGIN{printf "%dK", s/1000}')"
else
    window_str="$context_size"
fi

branch=""
[ -n "$cwd" ] && branch=$(ctx_branch "$cwd")

used_int=$(printf '%.0f' "${used_pct:-0}" 2>/dev/null || echo 0)
zone=$(ctx_zone "$used_int")

case "$zone" in
    red)    color="\033[31m" ;;
    yellow) color="\033[33m" ;;
    *)      color="\033[32m" ;;
esac
reset="\033[0m"

# --- bar ---
bar_len=$(ctx_setting '.statusline.bar_length' 8)
filled=$((used_int * bar_len / 100))
[ "$filled" -gt "$bar_len" ] && filled=$bar_len
empty=$((bar_len - filled))
bar=""
for ((i = 0; i < filled; i++)); do bar+="▮"; done
for ((i = 0; i < empty; i++)); do bar+="▯"; done

# --- turn count ---
# ctx.sh's turns.jsonl gets exactly one real-turn row per Stop event (plus
# occasional compaction-event rows, filtered out here) — an exact count,
# not an estimate, so reading it for a count (never for a token quantity)
# doesn't reintroduce the "hook-side approximation" problem.
turn_count="–"
show_turn_count=$(ctx_setting '.statusline.show_turn_count' true)
if [ "$show_turn_count" = "true" ]; then
    turns_log="$(ctx_session_dir "$session_id")/turns.jsonl"
    if [ -f "$turns_log" ]; then
        tc=$(jq -rs '[.[] | select(has("tokens_in"))] | length' "$turns_log" 2>/dev/null)
        [ -n "${tc:-}" ] && [ "$tc" -gt 0 ] 2>/dev/null && turn_count="$tc"
    fi
fi

# --- burn rate + forecast + per-turn cost ---
# Built only from numbers this script has itself observed straight from
# Claude Code (context_window.total_input_tokens/total_output_tokens, and
# cost.total_cost_usd — the same sources as the % and $ shown elsewhere),
# never from ctx.sh's hook-side estimate. statusLine renders far more often
# than once per turn, so a new point is only recorded when the token total
# actually changes. The file is never trimmed — statusline.burn_rate_window
# controls how much of it feeds the average (0 = the whole session, not
# just a recent slice), independently of how much history is kept on disk.
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)
current_total=$((${total_in:-0} + ${total_out:-0}))

history_file="$(ctx_session_dir "$session_id")/context_history.jsonl"
turns_left="–"
tok_per_turn="–"
spike=0
current_turn_cost=""

if [ "$current_total" -gt 0 ] 2>/dev/null; then
    last_recorded=$(tail -n 1 "$history_file" 2>/dev/null | jq -r '.tokens // empty' 2>/dev/null)
    if [ "$last_recorded" != "$current_total" ]; then
        jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson tokens "$current_total" --argjson cost "${cost_usd:-0}" \
            '{ts:$ts, tokens:$tokens, cost:$cost}' >> "$history_file" 2>/dev/null
    fi
fi

# "current" cost = delta between the last two real observations, i.e. what
# the most recently completed turn cost on its own (total_cost_usd itself
# only ever holds the cumulative session total). Stable across the several
# re-renders a single turn gets, since cost_usd itself doesn't change until
# the next turn completes.
if [ -f "$history_file" ]; then
    costs=$(tail -n 2 "$history_file" 2>/dev/null | jq -r '.cost // 0' 2>/dev/null)
    n=$(echo "$costs" | grep -c . 2>/dev/null || echo 0)
    if [ "${n:-0}" -ge 2 ] 2>/dev/null; then
        current_turn_cost=$(echo "$costs" | awk 'NR==1{a=$1} NR==2{b=$1} END{d=b-a; if(d<0)d=0; printf "%.4f", d}')
    elif [ "${n:-0}" -eq 1 ] 2>/dev/null; then
        current_turn_cost=$(echo "$costs" | awk '{printf "%.4f", $1}')
    fi
fi

if [ -f "$history_file" ]; then
    burn_window=$(ctx_setting '.statusline.burn_rate_window' 0)
    if [ "$burn_window" -gt 0 ] 2>/dev/null; then
        deltas=$(jq -r '.tokens' "$history_file" 2>/dev/null | tail -n "$burn_window")
    else
        deltas=$(jq -r '.tokens' "$history_file" 2>/dev/null)
    fi
    if [ -n "$deltas" ]; then
        spike_mult=$(ctx_setting '.statusline.spike_multiplier' 2)
        read -r avg spike <<< "$(echo "$deltas" | awk -v mult="$spike_mult" 'NF{a[NR]=$1} END{
            if (NR<2) { print "0 0"; exit }
            s=0; c=0
            for (i=2;i<=NR;i++){ d=a[i]-a[i-1]; if (d>0){ s+=d; c++ } }
            if (c==0) { print "0 0"; exit }
            avg=s/c
            last=a[NR]-a[NR-1]
            spiked=(c>=2 && last > avg*mult) ? 1 : 0
            printf "%.0f %d", avg, spiked
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
    total_cost_str=$(awk -v c="$cost_usd" 'BEGIN{printf "$%.2f", c}')
    if [ -n "$current_turn_cost" ]; then
        current_cost_str=$(awk -v c="$current_turn_cost" 'BEGIN{printf "$%.2f", c}')
        cost_str="current ${current_cost_str} total ${total_cost_str}"
    else
        cost_str="total ${total_cost_str}"
    fi
fi

# --- assemble ---
# Zone is conveyed by the bar's color alone — no redundant text label.
# turn/forecast/burn-rate are grouped into one comma-joined segment.
parts=("${color}${bar}${reset} ${used_int}% of ${window_str}")
[ -n "$branch" ] && parts+=("git:(${branch})")

burn_group=()
[ "$turn_count" != "–" ] && burn_group+=("turn ${turn_count}")
show_burn=$(ctx_setting '.statusline.show_burn_rate' true)
if [ "$show_burn" = "true" ]; then
    [ "$turns_left" != "–" ] && burn_group+=("≈${turns_left} turns left")
    if [ "$tok_per_turn" != "–" ]; then
        if [ "${spike:-0}" = "1" ]; then
            burn_group+=("\033[35m${tok_per_turn} tok/turn ⚡\033[0m")
        else
            burn_group+=("${tok_per_turn} tok/turn")
        fi
    fi
fi
if [ "${#burn_group[@]}" -gt 0 ]; then
    joined=""
    for g in "${burn_group[@]}"; do
        [ -n "$joined" ] && joined="${joined}, "
        joined="${joined}${g}"
    done
    parts+=("$joined")
fi

[ -n "$cost_str" ] && parts+=("${cost_str}")

result="[${model_name}]"
for p in "${parts[@]}"; do
    result="${result} | ${p}"
done

printf '%b\n' "$result"
