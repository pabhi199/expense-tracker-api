#!/bin/bash
# Claude Code statusline: model | context bar+% + token delta | cache % | total cost + turn delta
# Handles: missing jq, malformed/empty JSON, absent fields, read-only /tmp, non-numeric values,
# and null current_usage (before first API call / after /compact).

# --- Palette (raw codes) --- assign these below; logic never uses raw codes directly.
BOLD=$'\033[1m'; RESET=$'\033[0m'
CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[91m'
MAGENTA=$'\033[35m'; WHITE=$'\033[97m'; GRAY=$'\033[90m'
# More codes: 30-37 normal / 90-97 bright (black,red,green,yellow,blue,magenta,cyan,white), as \033[<n>m

# --- Color assignments --- change any value to restyle a tier; thresholds are below.
MODEL_NAME_COLOR="$CYAN";        PROMPT_COUNT_COLOR="$GRAY"
CTX_COLOR_OK="$GREEN";           CTX_COLOR_WARN="$YELLOW";        CTX_COLOR_CRIT="$RED"
TOKEN_COLOR_LOW="$GRAY";         TOKEN_COLOR_MID="$MAGENTA";       TOKEN_COLOR_HIGH="$YELLOW"
CACHE_COLOR_LOW="$GRAY";         CACHE_COLOR_MID="$CYAN";          CACHE_COLOR_HIGH="$GREEN"
TOTAL_COST_COLOR_OK="$WHITE";    TOTAL_COST_COLOR_WARN="$YELLOW";  TOTAL_COST_COLOR_CRIT="$RED"
TURN_COST_COLOR_OK="$GRAY";      TURN_COST_COLOR_WARN="$YELLOW";   TURN_COST_COLOR_CRIT="$RED"

# --- Thresholds --- all "value >= X" cutoffs.
CTX_PCT_YELLOW=60;      CTX_PCT_RED=85          # context window used %
TOKEN_DELTA_MAGENTA=2000; TOKEN_DELTA_YELLOW=8000 # token delta (input+output tokens/turn)
CACHE_PCT_CYAN=40;      CACHE_PCT_GREEN=70       # cache efficiency %
TOTAL_COST_YELLOW=1;    TOTAL_COST_RED=5         # total session cost, USD
TURN_COST_YELLOW=0.05;  TURN_COST_RED=0.25       # per-turn cost delta, USD (own scale, not total's)
STALE_CACHE_DAYS=2                               # prune this script's /tmp files older than N days

# --- Guards: no jq / empty / malformed JSON -----------------------------------
command -v jq >/dev/null 2>&1 || { echo "Claude Code (install jq for full statusline)"; exit 0; }
input=$(cat 2>/dev/null)
if [ -z "$input" ] || ! echo "$input" | jq -e . >/dev/null 2>&1; then
  echo "Claude Code (waiting for session data...)"; exit 0
fi

# is_num N: prints 1 if N looks numeric, else 0 (native bash regex, no subprocess)
is_num() { [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && echo 1 || echo 0; }

CACHE_DIR="${TMPDIR:-/tmp}"
{ find "$CACHE_DIR" -maxdepth 1 -name 'statusline-*' -mtime "+${STALE_CACHE_DAYS}" -delete; } >/dev/null 2>&1 || true

# Single jq call extracts every field at once (10 separate jq forks would otherwise be
# the single biggest cost per render). Fields are joined with \x1f (ASCII unit separator)
# rather than a tab: bash's `read` collapses consecutive tab/space delimiters, which would
# silently corrupt parsing whenever a field is empty (e.g. null current_usage) — \x1f avoids that.
JQ_FIELDS='[.model.display_name, .session_id, .prompt_id, .context_window.used_percentage,
  .context_window.context_window_size, .context_window.current_usage.output_tokens,
  .context_window.current_usage.input_tokens, .context_window.current_usage.cache_creation_input_tokens,
  .context_window.current_usage.cache_read_input_tokens, .cost.total_cost_usd]
  | map(if . == null then "" elif type == "string" then . else tostring end) | join("\u001f")'
IFS=$(printf '\x1f') read -r MODEL SESSION_ID PROMPT_ID PCT_RAW CTX_SIZE OUT_TOK IN_TOK CACHE_CREATE CACHE_READ TOTAL_COST \
  <<< "$(echo "$input" | jq -r "$JQ_FIELDS" 2>/dev/null)"

# Apply the same per-field defaults the old per-call jget() used
[ -z "$MODEL" ] && MODEL="Claude"
[ -z "$SESSION_ID" ] && SESSION_ID="nosession"
[ -z "$PCT_RAW" ] && PCT_RAW="0"
[ -z "$OUT_TOK" ] && OUT_TOK="0"
[ -z "$IN_TOK" ] && IN_TOK="0"
[ -z "$CACHE_CREATE" ] && CACHE_CREATE="0"
[ -z "$CACHE_READ" ] && CACHE_READ="0"
[ -z "$TOTAL_COST" ] && TOTAL_COST="0"
# PROMPT_ID and CTX_SIZE default to "" already (no action needed)

SESSION_ID_SAFE=$(echo "$SESSION_ID" | tr -cd 'A-Za-z0-9_-'); [ -z "$SESSION_ID_SAFE" ] && SESSION_ID_SAFE="nosession"

# Context window % (server-computed; always trust over any manual calc)
if [ "$(is_num "$PCT_RAW")" = "1" ]; then
  PCT=$(awk -v n="$PCT_RAW" 'BEGIN{p=int(n); if(p<0)p=0; if(p>100)p=100; print p}')
else
  PCT=0
fi

# Context window size, human-readable ("of 200k"); omitted entirely if absent/invalid
SIZE_HUMAN=""
if [ -n "$CTX_SIZE" ] && [ "$(is_num "$CTX_SIZE")" = "1" ]; then
  SIZE_HUMAN=$(awk -v n="$CTX_SIZE" 'BEGIN{
    if(n<=0){print ""; exit}
    if(n>=1000000) printf "%dM", n/1000000
    else if(n>=1000) printf "%dk", n/1000
    else printf "%d", n}')
fi

# Token delta: input_tokens + cache_creation_input_tokens + output_tokens this turn.
# This is real context growth: cache_read is excluded because it's content already in
# context from an earlier turn being reused, not new; the other three are all new.
[ "$(is_num "$OUT_TOK")" != "1" ] && OUT_TOK=0
[ "$(is_num "$IN_TOK")" != "1" ] && IN_TOK=0
[ "$(is_num "$CACHE_CREATE")" != "1" ] && CACHE_CREATE=0
GROWTH_TOK=$(awk -v o="$OUT_TOK" -v i="$IN_TOK" -v c="$CACHE_CREATE" 'BEGIN{printf "%d", o+i+c}')
TOKEN_DELTA=""
[ "$GROWTH_TOK" -gt 0 ] 2>/dev/null && TOKEN_DELTA=$(awk -v n="$GROWTH_TOK" 'BEGIN{if(n>=1000) printf "+%.1fk", n/1000; else printf "+%d", n}')
if [ "$GROWTH_TOK" -ge "$TOKEN_DELTA_YELLOW" ] 2>/dev/null; then TOKEN_COLOR="$TOKEN_COLOR_HIGH"
elif [ "$GROWTH_TOK" -ge "$TOKEN_DELTA_MAGENTA" ] 2>/dev/null; then TOKEN_COLOR="$TOKEN_COLOR_MID"
else TOKEN_COLOR="$TOKEN_COLOR_LOW"; fi

# Cache efficiency: share of this turn's input served from cache
[ "$(is_num "$CACHE_READ")" != "1" ] && CACHE_READ=0
CACHE_PCT=$(awk -v r="$CACHE_READ" -v i="$IN_TOK" -v c="$CACHE_CREATE" 'BEGIN{d=r+i+c; if(d<=0){print -1; exit} printf "%.0f", (r/d)*100}')

# Cost: total (real field) + turn delta (diffed against cached previous total, clamped >=0
# so a /clear resetting total_cost_usd to $0 never shows a negative turn delta)
[ "$(is_num "$TOTAL_COST")" != "1" ] && TOTAL_COST=0
COST_CACHE_FILE="${CACHE_DIR}/statusline-cost-${SESSION_ID_SAFE}"
PREV_COST=$(cat "$COST_CACHE_FILE" 2>/dev/null); [ "$(is_num "$PREV_COST")" != "1" ] && PREV_COST=0
TURN_COST=$(awk -v a="$TOTAL_COST" -v b="$PREV_COST" 'BEGIN{d=a-b; if(d<0)d=0; printf "%.4f", d}')
echo "$TOTAL_COST" > "$COST_CACHE_FILE" 2>/dev/null || true
TOTAL_FMT=$(awk -v n="$TOTAL_COST" 'BEGIN{printf "$%.2f", n}')
TURN_FMT=$(awk -v n="$TURN_COST" 'BEGIN{printf "$%.2f", n}')
if awk -v t="$TOTAL_COST" -v r="$TOTAL_COST_RED" 'BEGIN{exit !(t>=r)}'; then COST_COLOR="$TOTAL_COST_COLOR_CRIT"
elif awk -v t="$TOTAL_COST" -v y="$TOTAL_COST_YELLOW" 'BEGIN{exit !(t>=y)}'; then COST_COLOR="$TOTAL_COST_COLOR_WARN"
else COST_COLOR="$TOTAL_COST_COLOR_OK"; fi

# Prompt counter: bump only on a genuinely new prompt_id, cached per session
COUNT_FILE="${CACHE_DIR}/statusline-promptcount-${SESSION_ID_SAFE}"
LASTID_FILE="${CACHE_DIR}/statusline-promptlastid-${SESSION_ID_SAFE}"
PROMPT_COUNT=$(cat "$COUNT_FILE" 2>/dev/null); [ "$(is_num "$PROMPT_COUNT")" != "1" ] && PROMPT_COUNT=0
LAST_PROMPT_ID=$(cat "$LASTID_FILE" 2>/dev/null || echo "")
if [ -n "$PROMPT_ID" ] && [ "$PROMPT_ID" != "$LAST_PROMPT_ID" ]; then
  PROMPT_COUNT=$((PROMPT_COUNT + 1))
  echo "$PROMPT_COUNT" > "$COUNT_FILE" 2>/dev/null || true
  echo "$PROMPT_ID" > "$LASTID_FILE" 2>/dev/null || true
fi

# Context bar (10 blocks, rounded so 95-99% reads as a full bar, not stuck at 9/10)
FILLED=$(awk -v p="$PCT" 'BEGIN{f=int((p/10)+0.5); if(f>10)f=10; if(f<0)f=0; print f}')
EMPTY=$((10 - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v FILL "%${FILLED}s" && BAR="${FILL// /▮}"
[ "$EMPTY" -gt 0 ] && printf -v PAD "%${EMPTY}s" && BAR="${BAR}${PAD// /▯}"
if [ "$PCT" -ge "$CTX_PCT_RED" ]; then BAR_COLOR="$CTX_COLOR_CRIT"
elif [ "$PCT" -ge "$CTX_PCT_YELLOW" ]; then BAR_COLOR="$CTX_COLOR_WARN"
else BAR_COLOR="$CTX_COLOR_OK"; fi

# --- Assemble & print ----------------------------------------------------------
SIZE_PART=""; [ -n "$SIZE_HUMAN" ] && SIZE_PART=" of ${SIZE_HUMAN}"
TOKEN_PART=""; [ -n "$TOKEN_DELTA" ] && TOKEN_PART=" ${TOKEN_COLOR}${TOKEN_DELTA}${RESET}"

CACHE_PART=""
if [ "$CACHE_PCT" != "-1" ]; then
  if [ "$CACHE_PCT" -ge "$CACHE_PCT_GREEN" ] 2>/dev/null; then CACHE_COLOR="$CACHE_COLOR_HIGH"
  elif [ "$CACHE_PCT" -ge "$CACHE_PCT_CYAN" ] 2>/dev/null; then CACHE_COLOR="$CACHE_COLOR_MID"
  else CACHE_COLOR="$CACHE_COLOR_LOW"; fi
  CACHE_PART=" | ${CACHE_COLOR}cache ${CACHE_PCT}%${RESET}"
fi

TURN_PART=""
if awk -v t="$TURN_COST" 'BEGIN{exit !(t>0)}'; then
  if awk -v t="$TURN_COST" -v r="$TURN_COST_RED" 'BEGIN{exit !(t>=r)}'; then TURN_COLOR="$TURN_COST_COLOR_CRIT"
  elif awk -v t="$TURN_COST" -v y="$TURN_COST_YELLOW" 'BEGIN{exit !(t>=y)}'; then TURN_COLOR="$TURN_COST_COLOR_WARN"
  else TURN_COLOR="$TURN_COST_COLOR_OK"; fi
  TURN_PART=" ${TURN_COLOR}↑${TURN_FMT}${RESET}"
fi

echo "${BOLD}${MODEL_NAME_COLOR}${MODEL}${RESET} ${PROMPT_COUNT_COLOR}#${PROMPT_COUNT}${RESET} | ${BAR_COLOR}${BAR} ${PCT}%${SIZE_PART}${RESET}${TOKEN_PART}${CACHE_PART} | ${COST_COLOR}total ${TOTAL_FMT}${RESET}${TURN_PART}"
