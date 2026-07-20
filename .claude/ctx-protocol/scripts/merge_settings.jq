## merge_settings.jq — additively merge settings.fragment.json into an
## existing (possibly empty) settings.json without clobbering unrelated
## hooks, statusLine, or permission rules. Invoked as:
##   jq -s -f merge_settings.jq existing.json fragment.json
## Idempotent: re-running with the same fragment never duplicates entries.

def mergeEvent(existing; frag):
  (existing // []) as $e
  | (frag // []) as $f
  | ([$e[]?.hooks[]?.command]) as $existingCmds
  | $e + ($f | map(select(.hooks[0].command as $c | ($existingCmds | index($c)) == null)));

.[0] as $existing | .[1] as $frag |
$existing
| .statusLine = (if ($existing | has("statusLine")) then $existing.statusLine else $frag.statusLine end)
| .permissions.allow = (((($existing.permissions.allow) // []) + ($frag.permissions.allow // [])) | unique)
| .hooks.SessionStart = mergeEvent($existing.hooks.SessionStart; $frag.hooks.SessionStart)
| .hooks.Stop         = mergeEvent($existing.hooks.Stop; $frag.hooks.Stop)
| .hooks.PreCompact   = mergeEvent($existing.hooks.PreCompact; $frag.hooks.PreCompact)
| .hooks.PostCompact  = mergeEvent($existing.hooks.PostCompact; $frag.hooks.PostCompact)
| .hooks.SessionEnd   = mergeEvent($existing.hooks.SessionEnd; $frag.hooks.SessionEnd)
