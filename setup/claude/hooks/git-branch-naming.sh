#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: remind git-flow branch naming conventions when a Bash command
# creates a branch — checkout -b/-B, switch -c/-C/--create, worktree add -b/-B.

command=$(jq -r '.tool_input.command')

# `git` must sit at a real command position: string start, or after ; & | ( — otherwise a
# git-shaped string inside a quoted argument matches. Without the anchor, all of these fire:
#   git commit -m "fix git checkout -b handling"   grep -rn "git checkout -b" .
#   git log --grep="git checkout -b"               legit checkout -b x      (no word boundary)
# Only option-shaped tokens may sit between `git` and the subcommand. Allowing arbitrary
# tokens there is precisely what puts those false positives back, so the cost is accepted:
# a global option whose value contains whitespace (git -C "/path with space" checkout -b x)
# does not match. `git branch <name>` is also uncovered — it needs its own alternative plus
# exclusions for -d/--list/--set-upstream-to. And text that merely quotes a branch-creating
# command at a command position (heredocs, docs about git) still matches; a regex over the
# raw command string cannot tell that apart.
# Regression suite: ./git-branch-naming.test.sh — 35 cases, run it when touching this.
cmd_pos='(^|[;&|(]|[[:space:]]&&[[:space:]]|[[:space:]]\|\|[[:space:]])[[:space:]]*'
env_prefix='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
git_globals='(-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?[[:space:]]+)*'
create_sub='(checkout[[:space:]]+-[bB]|switch[[:space:]]+(-[cC]|--create)|worktree[[:space:]]+add[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-[bB])'
branch_create_re="${cmd_pos}${env_prefix}git[[:space:]]+${git_globals}${create_sub}"

if [[ $command =~ $branch_create_re ]]; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"GIT-FLOW BRANCH NAMING: Only feature/*, release/*, hotfix/* are valid prefixes. Commit types (feat/, fix/, refactor/) are NOT branch prefixes. Non-urgent fixes and refactors MUST use feature/*. hotfix/* is ONLY for production emergencies (branch from main)."}}
EOF
fi
