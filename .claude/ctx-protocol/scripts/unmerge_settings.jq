## unmerge_settings.jq — reverse of merge_settings.jq for `install.sh
## --uninstall`. Removes exactly the entries the fragment would have added
## (matched by exact command string), then drops any container left empty.
## Invoked as: jq -s -f unmerge_settings.jq existing.json fragment.json

def removeEvent(existing; frag):
  (existing // []) as $e
  | ([frag[]?.hooks[]?.command]) as $fragCmds
  | $e | map(select(.hooks[0].command as $c | ($fragCmds | index($c)) == null));

.[0] as $existing | .[1] as $frag |
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
