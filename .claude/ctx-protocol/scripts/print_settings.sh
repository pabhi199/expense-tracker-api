#!/bin/bash
# print_settings.sh — prints the effective (defaults + local override) merged
# settings, for the /ctx-settings command's inline execution.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh" 2>/dev/null || exit 0
ctx_settings
