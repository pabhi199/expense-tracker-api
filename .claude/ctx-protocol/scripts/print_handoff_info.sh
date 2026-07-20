#!/bin/bash
# print_handoff_info.sh — small helper for the /handoff command: prints the
# branch, target path, and backup setting so the command body can tell
# Claude exactly where to write without duplicating lib.sh logic inline.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh" 2>/dev/null || exit 0

dir="${1:-$PWD}"
echo "branch: $(ctx_branch "$dir")"
echo "path: $(ctx_handoff_path "$dir")"
echo "keep_backup: $(ctx_setting '.handoff.keep_backup' true)"
