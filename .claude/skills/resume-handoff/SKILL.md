---
name: resume-handoff
description: Load the saved handoff for this project + branch into the current conversation. Use when the user runs /resume-handoff, or asks to resume/restore prior session state.
---

# Resume Handoff

This is the only way ctx-protocol ever adds anything to your context — do this inline, in the current conversation, not via a subagent.

1. Run `bash .claude/ctx-protocol/scripts/ctx.sh print-handoff-content` with the Bash tool. It prints the saved handoff for the current project + branch, or a fallback message if none exists.
2. If a handoff was found: briefly restate the current state back to the user in 1-2 sentences (pull from the `Summary:` line and unresolved items), then continue the work from the unresolved items.
3. If none was found: tell the user there's no saved handoff for this branch yet, and that `/handoff` creates one.
