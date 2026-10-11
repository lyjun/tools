#!/bin/bash
# End-to-end: pipe a PreToolUse payload into the REAL hook file and assert on its stdout.
# This tests what is actually installed, not a copy of the regex.

HOOK="$HOME/.claude/hooks/git-branch-naming.sh"
FAILED=0
FIRED=0
SKIPPED=0

check() {
  local expect="$1" cmd="$2" out got
  out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | "$HOOK" 2>/dev/null)
  if [[ -n $out ]]; then got=FIRE; else got=SKIP; fi
  if [[ $got == FIRE ]]; then FIRED=$((FIRED+1)); else SKIPPED=$((SKIPPED+1)); fi
  if [[ $got == "$expect" ]]; then
    printf 'ok   %-4s %s\n' "$got" "$cmd"
  else
    printf 'FAIL want=%s got=%s  %s\n' "$expect" "$got" "$cmd"
    FAILED=1
  fi
}

echo "hook: $HOOK"
echo

echo "-- false positives that the OLD regex fired on (must SKIP now) --"
check SKIP 'git commit -m "fix git checkout -b handling"'
check SKIP 'git commit -m "chore: document git switch -c"'
check SKIP 'grep -rn "git checkout -b" .'
check SKIP 'git log --grep="git checkout -b"'
check SKIP 'legit checkout -b x'
check SKIP 'echo "run git checkout -b feature/x first"'
check SKIP 'git commit -m "note about checkout -b"'

echo
echo "-- branch-creating forms (must FIRE) --"
check FIRE 'git checkout -b feature/plain'
check FIRE 'git switch -c feature/plain-switch'
check FIRE 'git checkout -B feature/force-b'
check FIRE 'git switch -C feature/force-c'
check FIRE 'git switch --create feature/long-create'
check FIRE 'git worktree add -b feature/wt ../wt'
check FIRE 'git worktree add -B feature/wt-force ../wt'
check FIRE 'git -C /repo checkout -b feature/dashC'
check FIRE 'git -c user.name=x checkout -b feature/dashc-cfg'
check FIRE 'git --git-dir=/x checkout -b feature/gitdir'
check FIRE 'git -C /path -c core.pager=cat checkout -b feature/two-opts'
check FIRE 'GIT_DIR=/x git checkout -b feature/envprefix'
check FIRE 'git   checkout   -b feature/extra-spaces'
check FIRE 'git -C /repo worktree add -b feature/wt2 ../wt2'

echo
echo "-- command-position variants (must FIRE) --"
check FIRE 'cd /a && git checkout -b feature/compound'
check FIRE 'cd /a; git switch -c feature/semicolon'
check FIRE '[[ -d /tmp ]] && git switch -c feature/conditional'
check FIRE 'make build || git checkout -b feature/orelse'
check FIRE '(git checkout -b feature/subshell)'

echo
echo "-- non-creating git commands (must SKIP) --"
check SKIP 'git checkout main'
check SKIP 'git switch main'
check SKIP 'git branch -d feature/old'
check SKIP 'git log --oneline'
check SKIP 'git worktree add ../wt existing-branch'
check SKIP 'git worktree list'
check SKIP 'echo "no-git-here"'

echo
echo "-- documented gaps, asserted so they stay visible --"
check SKIP 'git branch feature/via-branch-subcommand'
check SKIP 'git -C "/path with space" checkout -b feature/quoted'

echo
echo "-- malformed input robustness (must SKIP, must not crash) --"
printf '%s' '{"tool_input":{}}'        | "$HOOK" >/dev/null 2>&1; echo "  missing .command   exit=$?"
printf '%s' '{}'                       | "$HOOK" >/dev/null 2>&1; echo "  missing .tool_input exit=$?"
printf '%s' '{"tool_input":{"command":null}}' | "$HOOK" >/dev/null 2>&1; echo "  JSON null          exit=$?"
printf '%s' ''                         | "$HOOK" >/dev/null 2>&1; echo "  empty stdin        exit=$?"

echo
echo "fired=$FIRED skipped=$SKIPPED"
if [[ $FAILED -eq 0 ]]; then echo "VERDICT: ok"; else echo "VERDICT: error"; fi
exit $FAILED
