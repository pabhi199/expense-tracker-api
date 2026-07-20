## settings_merge.jq — additively merge or unmerge settings.fragment.json
## against an existing (possibly empty) settings.json, without touching
## unrelated hooks, statusLine, or permission rules. Invoked as:
##   jq -s --arg mode install|uninstall -f settings_merge.jq existing.json fragment.json
## Idempotent in both directions: re-running install (or uninstall) with the
## same fragment never duplicates (or double-removes) anything.

def mergeEvent(existing; frag):
  (existing // []) as $e
  | (frag // []) as $f
  | ([$e[]?.hooks[]?.command]) as $existingCmds
  | $e + ($f | map(select(.hooks[0].command as $c | ($existingCmds | index($c)) == null)));

def removeEvent(existing; frag):
  (existing // []) as $e
  | ([frag[]?.hooks[]?.command]) as $fragCmds
  | $e | map(select(.hooks[0].command as $c | ($fragCmds | index($c)) == null));

.[0] as $existing | .[1] as $frag |
if $mode == "uninstall" then
  $existing
  | (if ($existing.statusLine? == $frag.statusLine) then del(.statusLine) else . end)
  | .permissions.allow = ((($existing.permissions.allow) // []) - ($frag.permissions.allow // []))
  | .hooks.SessionStart = removeEvent($existing.hooks.SessionStart; $frag.hooks.SessionStart)
  | .hooks.Stop         = removeEvent($existing.hooks.Stop; $frag.hooks.Stop)
  | .hooks.PreCompact   = removeEvent($existing.hooks.PreCompact; $frag.hooks.PreCompact)
  | .hooks.PostCompact  = removeEvent($existing.hooks.PostCompact; $frag.hooks.PostCompact)
  | .hooks.SessionEnd   = removeEvent($existing.hooks.SessionEnd; $frag.hooks.SessionEnd)
  | (if ((.permissions.allow // []) | length) == 0 then del(.permissions.allow) else . end)
  | (if ((.permissions // {}) | length) == 0 then del(.permissions) else . end)
  | (if ((.hooks.SessionStart // []) | length) == 0 then del(.hooks.SessionStart) else . end)
  | (if ((.hooks.Stop // []) | length) == 0 then del(.hooks.Stop) else . end)
  | (if ((.hooks.PreCompact // []) | length) == 0 then del(.hooks.PreCompact) else . end)
  | (if ((.hooks.PostCompact // []) | length) == 0 then del(.hooks.PostCompact) else . end)
  | (if ((.hooks.SessionEnd // []) | length) == 0 then del(.hooks.SessionEnd) else . end)
  | (if ((.hooks // {}) | length) == 0 then del(.hooks) else . end)
else
  $existing
  | .statusLine = (if ($existing | has("statusLine")) then $existing.statusLine else $frag.statusLine end)
  | .permissions.allow = (((($existing.permissions.allow) // []) + ($frag.permissions.allow // [])) | unique)
  | .hooks.SessionStart = mergeEvent($existing.hooks.SessionStart; $frag.hooks.SessionStart)
  | .hooks.Stop         = mergeEvent($existing.hooks.Stop; $frag.hooks.Stop)
  | .hooks.PreCompact   = mergeEvent($existing.hooks.PreCompact; $frag.hooks.PreCompact)
  | .hooks.PostCompact  = mergeEvent($existing.hooks.PostCompact; $frag.hooks.PostCompact)
  | .hooks.SessionEnd   = mergeEvent($existing.hooks.SessionEnd; $frag.hooks.SessionEnd)
end
