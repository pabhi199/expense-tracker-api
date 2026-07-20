#!/bin/bash
# activity-logger.sh — logs every tool call, skill, subagent, and lifecycle
# event Claude Code fires during a prompt, to one clean NDJSON file —
# including which model actually handled it, even inside subagents/skills.
#
# Wire this to multiple hook events (see settings.json snippet below).
# It never blocks: always exits 0, and any internal failure is swallowed
# so a broken jq/log-write never interrupts your session.

set -u
LOG_FILE="${CLAUDE_ACTIVITY_LOG:-$HOME/.claude/activity.ndjson}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

input=$(cat)

{
  # An explicit model override on the tool call itself (Agent/Task calls
  # that pass model: "haiku", etc).
  explicit_model=$(echo "$input" | jq -r '.tool_input.model // empty' 2>/dev/null)

  # The model actually driving *this* transcript (parent turn, or the
  # subagent's own transcript when the event comes from inside one —
  # hook payloads point transcript_path at whichever is relevant).
  transcript_path=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  turn_model=""
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    turn_model=$(tail -n 200 "$transcript_path" 2>/dev/null \
      | jq -rs '[.[] | select(.type=="assistant") | .message.model // empty] | last // empty' 2>/dev/null)
  fi

  # A Skill call's own frontmatter can pin a model/context (our
  # list-files / explore-file skills set model: haiku) — surface that
  # even though it never appears in tool_input.
  tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  skill_model=""
  skill_context=""
  if [ "$tool_name" = "Skill" ]; then
    skill_name=$(echo "$input" | jq -r '.tool_input.skill // .tool_input.name // empty' 2>/dev/null)
    for base in "${CLAUDE_PROJECT_DIR:-.}/.claude/skills" "$HOME/.claude/skills"; do
      f="$base/$skill_name/SKILL.md"
      if [ -n "$skill_name" ] && [ -f "$f" ]; then
        skill_model=$(awk -F': *' '/^model:/{print $2; exit}' "$f" | tr -d '\r')
        skill_context=$(awk -F': *' '/^context:/{print $2; exit}' "$f" | tr -d '\r')
        break
      fi
    done
  fi

  model="${explicit_model:-${skill_model:-${turn_model:-unknown}}}"

  echo "$input" | jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg model "$model" \
    --arg skill_context "$skill_context" '
    {
      ts: $ts,
      session: (.session_id // "unknown" | .[0:8]),
      event: (.hook_event_name // "unknown"),
      tool: (.tool_name // null),
      model: $model,
      context: (if $skill_context == "" then null else $skill_context end),
      detail: (
        # Best-effort human-readable detail per event/tool shape.
        if .tool_name == "Skill" then (.tool_input.name // .tool_input.skill // "skill")
        elif .tool_name == "Agent" or .tool_name == "Task" then
          (.tool_input.description // .tool_input.subagent_type // "agent task")
        elif .tool_name == "Bash" then (.tool_input.command // "" | .[0:80])
        elif .tool_name == "Read" or .tool_name == "Write" or .tool_name == "Edit" then
          (.tool_input.file_path // "")
        elif .tool_name == "AskUserQuestion" then
          ("asked: " + (.tool_input.questions[0].question // "" | .[0:60]))
        elif .hook_event_name == "UserPromptSubmit" then
          (.prompt // "" | .[0:60])
        elif .hook_event_name == "SubagentStop" then
          ("subagent finished: " + (.subagent_type // "unknown"))
        elif .hook_event_name == "Stop" then "turn complete"
        elif .hook_event_name == "SessionStart" then "session started"
        else (.tool_input // "" | tostring | .[0:60])
        end
      )
    }
  ' >> "$LOG_FILE" 2>/dev/null
} || true

exit 0
