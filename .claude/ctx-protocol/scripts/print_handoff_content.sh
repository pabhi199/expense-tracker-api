#!/bin/bash
# print_handoff_content.sh <dir> — prints the saved handoff for this
# project+branch, or a fallback message. Used by /resume-handoff's inline
# execution, which is the only place ctx-protocol injects into context.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh" 2>/dev/null || exit 0

dir="${1:-$PWD}"
p=$(ctx_handoff_path "$dir")
if [ -f "$p" ]; then
    cat "$p"
else
    echo "No handoff found for this project/branch yet. Run /handoff to create one."
fi
