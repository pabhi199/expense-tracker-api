#!/bin/bash
# install.sh — wires ctx-protocol into a project. Everything ctx-protocol
# owns lives in this folder; the only files this script touches outside it
# are ones Claude Code *requires* at fixed locations (.claude/settings.json
# for hooks/statusLine, .claude/commands/ for slash commands, and
# .git/info/exclude for keeping runtime data out of git). Safe to re-run —
# every change is additive and matched by exact content, so running twice
# never duplicates anything.
#
# Usage:
#   bash install.sh                    install into the project this folder
#                                       sits under (<project>/.claude/ctx-protocol)
#   bash install.sh --project-dir DIR  install into a different project root
#   bash install.sh --uninstall        remove everything this script added
#   bash install.sh --force            overwrite customized installed commands
set -u

CTX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNINSTALL=0
FORCE=0
PROJECT_ROOT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall) UNINSTALL=1 ;;
        --force) FORCE=1 ;;
        --project-dir) shift; PROJECT_ROOT="${1:-}" ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

if [ -z "$PROJECT_ROOT" ]; then
    # Default layout: <project>/.claude/ctx-protocol
    PROJECT_ROOT="$(cd "$CTX_DIR/../.." && pwd)"
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "install.sh: jq is required and not on PATH" >&2
    exit 1
fi

CLAUDE_DIR="$PROJECT_ROOT/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
FRAGMENT="$CTX_DIR/settings.fragment.json"
mkdir -p "$CLAUDE_DIR" "$SKILLS_DIR"

echo "ctx-protocol: target project = $PROJECT_ROOT"

# --- skills (handoff, resume-handoff, ctx-settings) ------------------
for src_dir in "$CTX_DIR"/skills/*/; do
    name="$(basename "$src_dir")"
    src="$src_dir/SKILL.md"
    dest_dir="$SKILLS_DIR/$name"
    dest="$dest_dir/SKILL.md"
    if [ "$UNINSTALL" = "1" ]; then
        if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
            rm -rf "$dest_dir"
            echo "  removed .claude/skills/$name/"
        elif [ -f "$dest" ]; then
            echo "  skipped .claude/skills/$name/ (modified since install, left in place)"
        fi
        continue
    fi
    if [ -f "$dest" ] && ! cmp -s "$src" "$dest" && [ "$FORCE" != "1" ]; then
        echo "  skipped .claude/skills/$name/ (differs from template; rerun with --force to overwrite)"
        continue
    fi
    mkdir -p "$dest_dir"
    cp "$src" "$dest"
    echo "  installed .claude/skills/$name/"
done

# --- settings.json ------------------------------------------------------
[ -f "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"

existing_statusline=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
if [ "$UNINSTALL" != "1" ] && [ -n "$existing_statusline" ] && [[ "$existing_statusline" != *"ctx-protocol/scripts/statusline.sh"* ]]; then
    echo "  NOTE: .claude/settings.json already has a different statusLine (\"$existing_statusline\") — leaving it as-is. Merge ctx-protocol's statusLine from settings.fragment.json manually if you want it." >&2
fi

merge_script="$CTX_DIR/scripts/merge_settings.jq"
[ "$UNINSTALL" = "1" ] && merge_script="$CTX_DIR/scripts/unmerge_settings.jq"

backup="$SETTINGS_FILE.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp "$SETTINGS_FILE" "$backup"

tmp="$(mktemp)"
if jq -s -f "$merge_script" "$SETTINGS_FILE" "$FRAGMENT" > "$tmp" 2>/dev/null && jq empty "$tmp" 2>/dev/null; then
    mv "$tmp" "$SETTINGS_FILE"
    rm -f "$backup"
    echo "  updated .claude/settings.json"
else
    rm -f "$tmp"
    echo "  ERROR: settings.json merge failed — left original untouched (backup was at $backup, restored)" >&2
    mv "$backup" "$SETTINGS_FILE" 2>/dev/null
    exit 1
fi

# --- git exclude ----------------------------------------------------------
if [ -d "$PROJECT_ROOT/.git" ]; then
    exclude_file="$PROJECT_ROOT/.git/info/exclude"
    mkdir -p "$(dirname "$exclude_file")"
    touch "$exclude_file"
    line=".claude/ctx-protocol/data/"
    if [ "$UNINSTALL" = "1" ]; then
        if grep -qF "$line" "$exclude_file" 2>/dev/null; then
            grep -vF "$line" "$exclude_file" | grep -vF "# ctx-protocol runtime data (local only, never shared)" > "$exclude_file.tmp" 2>/dev/null
            mv "$exclude_file.tmp" "$exclude_file"
            echo "  removed $line from .git/info/exclude"
        fi
    else
        if ! grep -qF "$line" "$exclude_file" 2>/dev/null; then
            printf '\n# ctx-protocol runtime data (local only, never shared)\n%s\n' "$line" >> "$exclude_file"
            echo "  added $line to .git/info/exclude"
        fi
    fi
fi

if [ "$UNINSTALL" = "1" ]; then
    echo "ctx-protocol: uninstalled. Delete .claude/ctx-protocol/ yourself if you want it fully gone."
else
    echo "ctx-protocol: installed. Try /handoff, /resume-handoff, /ctx-settings in your next session."
fi
