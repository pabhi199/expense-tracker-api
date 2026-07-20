---
name: ctx-settings
description: Show ctx-protocol's effective settings and edit the local override. Use when the user runs /ctx-settings, or asks to view/change ctx-protocol configuration (zones, notices, handoff model, etc).
---

# ctx-settings

1. Run `bash .claude/ctx-protocol/scripts/ctx.sh print-settings` with the Bash tool. It prints the effective settings — shipped defaults deep-merged with the local override.
2. If the user just wants to see settings, show them the output.
3. If the user asked to change a setting, edit `.claude/ctx-protocol/data/settings.local.json` directly (create it with just the overridden keys if it doesn't exist yet — it's deep-merged over `.claude/ctx-protocol/settings.default.json`, so only include the keys being overridden, not the whole file).
