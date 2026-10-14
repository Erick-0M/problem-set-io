#!/bin/bash
# Stop hook: warns if HEAD has commits not on the upstream remote,
# enforcing the CLAUDE.md rule "never report work as committed until
# the branch is visible on GitHub."
cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
msg=""

if [ -z "$upstream" ]; then
  msg="Branch '$branch' has no upstream — it has never been pushed."
else
  ahead=$(git rev-list --count "$upstream"..HEAD 2>/dev/null)
  if [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
    msg="$ahead unpushed commit(s) on '$branch' — run git push before reporting done."
  fi
fi

if [ -n "$msg" ]; then
  printf '{"systemMessage": %s}' "$(printf '%s' "$msg" | jq -Rs .)"
fi
