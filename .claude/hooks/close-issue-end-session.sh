#!/bin/bash
# PostToolUse (Bash) hook: ends the session once `gh issue close` succeeds,
# enforcing the CLAUDE.md rule that closing an issue ends the Claude session.
input=$(cat)

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
success=$(printf '%s' "$input" | jq -r 'if .tool_response.success == null then true else .tool_response.success end')

echo "$cmd" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+issue[[:space:]]+close([[:space:]]|$)' || exit 0
[ "$success" = "true" ] || exit 0

printf '{"continue": false, "stopReason": %s}' "$(printf '%s' "Issue closed via gh issue close — ending session per repo workflow (CLAUDE.md)." | jq -Rs .)"
