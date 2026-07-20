---
name: handoff
description: Snapshot the current working state to ctx-protocol's durable handoff file. Use when the user runs /handoff, or asks to save/snapshot session state before a break or risky change.
---

# Handoff

Write (or overwrite) a durable handoff file for the current project + branch so this work can be resumed later, even in a fresh session.

1. Run `bash .claude/ctx-protocol/scripts/print_handoff_info.sh` with the Bash tool. It prints the target `path`, the current `branch`, and whether `keep_backup` is enabled.
2. If `keep_backup` is `true` and the file at `path` already exists, copy it to the same path with a `.1` suffix first (`cp path path.1`).
3. Using the Write tool, write the file at `path` with exactly this structure:

```
Summary: <one line, under 100 chars, current state of the task>

## What I was doing
<2-4 short bullets, grounded in this conversation>

## Decisions made
<bullets, or "None recorded.">

## Unresolved items
<bullets, or "None.">

## Files touched
<bullet list of files this session has read or edited, or "None identified.">
```

4. Run `bash .claude/ctx-protocol/scripts/print_settings.sh` and check `.handoff.store_in_repo`. If `true`, run `git add -f <path>` so the handoff gets committed with the branch.
5. Confirm to the user in one line that the handoff was saved, and where.

If the user passed extra text with the command, fold it into the summary/notes as their explicit note about current state.
