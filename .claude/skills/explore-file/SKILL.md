---
name: explore-file
description: Explore a single specific file in depth using a lightweight Haiku-model subagent, then report back a summary. Use when the user asks to explore, investigate, or summarize one particular file by path.
model: haiku
---

# Explore File

Dispatch a focused, cheap exploration of exactly one file using a background agent running on the Haiku model, then relay its findings.

1. Determine the target file path from the skill argument. If none was given, ask the user which file to explore.
2. Confirm the path looks like a real file reference — don't invent one.
3. Launch the Agent tool with:
   - `subagent_type: general-purpose`
   - `model: haiku`
   - a self-contained prompt containing the exact file path, asking the agent to read the file and report: what it does, its main exports/functions/classes, and anything notable (bugs, TODOs, unusual patterns). Ask for the response to stay under 200 words.
4. Relay the agent's findings to the user in your own words, citing the file path.

This skill is for exploring one named file only. For broader project exploration, use `/list-files` or the Explore agent directly instead.
