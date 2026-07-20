#!/bin/bash
# Claude Code statusline with usage limits
input=$(cat)

# === Extract from JSON ===
current_dir=$(echo "$input" | jq -r '.workspace.current_dir' | sed 's|\\|/|g')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir' | sed 's|\\|/|g')
model_name=$(echo "$input" | jq -r '.model.display_name')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
transcript=$(echo "$input" | jq -r '.transcript_path' | sed 's|\\|/|g')
mcps=$({
    # User-configured MCP servers from settings files
    for f in "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" \
             "$project_dir/.claude/settings.json" "$project_dir/.claude/settings.local.json"; do
        [ -f "$f" ] && jq -r '.mcpServers // {} | keys[]' "$f" 2>/dev/null
    done
    # Plugin-provided MCP servers from installed plugin cache
    find "$HOME/.claude/plugins/cache" -name ".mcp.json" -exec jq -r 'keys[]' {} \; 2>/dev/null
} | sort -u | wc -l)
mcps=$((mcps + 0))  # ensure numeric

# === Git branch ===
cd "$current_dir" 2>/dev/null || cd "$project_dir" 2>/dev/null
branch=$(git -c core.useReplaceRefs=false -c gc.auto=0 branch --show-current 2>/dev/null)
project=$(basename "$current_dir")

# === Session time ===
# Claude Code reuses transcript files across sessions.
# Detect current session start by finding the last gap >30 min in timestamps.
session_time="0m"
if [ -f "$transcript" ]; then
    session_time=$(python3 - "$transcript" << 'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta
try:
    prev_ts = None
    session_start = None
    GAP = timedelta(minutes=30)
    filepath = sys.argv[1]
    size = __import__('os').path.getsize(filepath)
    with open(filepath, encoding='utf-8', errors='replace') as f:
        # For large files, seek to last 500KB (covers even multi-hour sessions)
        if size > 500000:
            f.seek(size - 500000)
            f.readline()  # skip partial line after seek
        for line in f:
            try:
                ts_str = json.loads(line).get("timestamp")
                if not ts_str:
                    continue
                ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                if prev_ts is None or (ts - prev_ts) > GAP:
                    session_start = ts
                prev_ts = ts
            except Exception:
                pass
    if session_start:
        elapsed = int((datetime.now(timezone.utc) - session_start).total_seconds() / 60)
        print(f"{elapsed // 60}h {elapsed % 60}m" if elapsed >= 60 else f"{elapsed}m")
    else:
        print("0m")
except Exception:
    print("0m")
PYEOF
)
fi

# === Context bar ===
used_int=$(printf "%.0f" "$used_pct")
context_tokens=$(echo "$used_pct $context_size" | awk '{printf "%.0f", $1 * $2 / 100}')
if [ "$context_tokens" -ge 1000 ] 2>/dev/null; then
    tokens_display="$((context_tokens / 1000))K"
else
    tokens_display="${context_tokens}"
fi
if [ "$context_size" -ge 1000 ] 2>/dev/null; then
    context_display="$((context_size / 1000))K"
else
    context_display="${context_size}"
fi

bar_len=6
filled=$((used_int * bar_len / 100))
empty=$((bar_len - filled))
if [ "$used_int" -lt 50 ]; then
    ctx_color="\033[32m"
elif [ "$used_int" -lt 80 ]; then
    ctx_color="\033[33m"
else
    ctx_color="\033[31m"
fi
bar="${ctx_color}"
for ((i=0; i<filled; i++)); do bar+="━"; done
for ((i=0; i<empty; i++)); do bar+="━"; done
bar+="\033[0m"

# === Build output ===
parts=("[${model_name}]")
parts+=("${bar} ${used_int}% (${tokens_display}/${context_display})")
parts+=("${project}")
[ -n "$branch" ] && parts+=("git:(${branch})")
[ "$mcps" -gt 0 ] 2>/dev/null && parts+=("${mcps} MCPs")
parts+=("⏱ ${session_time}")

result=""
for i in "${!parts[@]}"; do
    if [ "$i" -eq 0 ]; then
        result="${parts[$i]}"
    else
        result="$result | ${parts[$i]}"
    fi
done

printf '%b\n' "$result"