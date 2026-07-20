#!/bin/bash
# activity-view.sh — pretty-print the activity log as a clean timeline.
#
# Usage:
#   ./activity-view.sh              # most recent session
#   ./activity-view.sh <session8>   # a specific session (8-char prefix)
#   ./activity-view.sh --all        # everything, all sessions

LOG_FILE="${CLAUDE_ACTIVITY_LOG:-$HOME/.claude/activity.ndjson}"

if [ ! -f "$LOG_FILE" ]; then
  echo "No activity log yet at $LOG_FILE"
  exit 0
fi

icon_for() {
  case "$1" in
    UserPromptSubmit) echo "💬" ;;
    PreToolUse)        echo "→ " ;;
    PostToolUse)       echo "✓ " ;;
    SubagentStop)      echo "↩ " ;;
    Stop)              echo "■ " ;;
    SessionStart)      echo "▶ " ;;
    *)                 echo "• " ;;
  esac
}

target="${1:-}"

if [ "$target" == "--all" ]; then
  filter="."
elif [ -n "$target" ]; then
  filter="select(.session == \"$target\")"
else
  # default: most recent session id in the file
  latest=$(tail -n 200 "$LOG_FILE" | jq -r '.session' | tail -n 1)
  filter="select(.session == \"$latest\")"
  echo "Showing session: $latest  (pass --all for everything)"
fi

echo "-------------------------------------------------------------------------------------"
jq -c "$filter" "$LOG_FILE" | while read -r line; do
  ts=$(echo "$line" | jq -r '.ts' | cut -dT -f2 | cut -d: -f1,2,3)
  ev=$(echo "$line" | jq -r '.event')
  tool=$(echo "$line" | jq -r '.tool // ""')
  model=$(echo "$line" | jq -r '.model // "unknown"')
  ctx=$(echo "$line" | jq -r '.context // ""')
  detail=$(echo "$line" | jq -r '.detail // ""')
  icon=$(icon_for "$ev")

  if [ -n "$ctx" ]; then
    model="$model/$ctx"
  fi

  if [ -n "$tool" ] && [ "$tool" != "null" ]; then
    printf "[%s] %s%-16s %-10s [%-14s] %s\n" "$ts" "$icon" "$ev" "$tool" "$model" "$detail"
  else
    printf "[%s] %s%-16s [%-14s] %s\n" "$ts" "$icon" "$ev" "$model" "$detail"
  fi
done
echo "-------------------------------------------------------------------------------------"