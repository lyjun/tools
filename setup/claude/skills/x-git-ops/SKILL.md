---
name: x-git-ops
description: Git workflow rules and standardized commits — branch protection on main/master/develop/release/*, Git Flow branch naming, pre-commit checks, commit message conventions (feat/fix/perf/refactor/test/docs/build/ci/chore/revert/style), squash/amend, push tracking, cherry-pick, rebase/amend safety. Use when about to run any git mutation (commit, branch create/checkout, push, rebase, amend, cherry-pick), operate on protected branches, set up a feature branch, or create/squash/amend a commit.
user-invocable: true
model: haiku
---

# Git Operations

This skill is an index. The **always-on guards** below apply to every git mutation;
load the matching reference for the specific operation's detailed procedure.

| Operation | Reference |
|-----------|-----------|
| Create commit / squash / amend | `references/commit.md` |
| Rebase / cherry-pick / push / split commits / create branch | `references/workflow.md` |

When invoked bare (`/x-git-ops` with no prompt), the intended operation is ambiguous —
inspect `git status` / `git log --oneline` and ask the user which operation they want
before loading a reference.

## Branch Protection (mandatory)

On `main`, `master`, `develop`, `release/*`: **never modify code directly**.
Ask branch name via AskUserQuestion, create and switch before implementing.
On feature branch → proceed directly.

## Branch Naming & Base (mandatory)

建立 branch 時：`feature/*` 從 `develop` 分、`hotfix/*` 從 `main` 分（Git Flow；非緊急 fix 歸 `feature/*`）。完整命名規則、base 指定與事後驗證指令見 `references/workflow.md`。

## Commit Rules (mandatory)

**Only commit when user explicitly requests** ("commit", "請 commit", "幫我 commit").
**Do NOT enter plan mode** for commits, squash, or rebase — execute directly.

**Forbidden**: Auto-committing after tasks, proactively deciding to commit, including commit steps in test/verify tasks.
**Forbidden**: After any review/fix skill makes changes, do not auto-commit or amend. Report modification summary only and let user decide whether to commit. Such fixes must be new commits, not amends of existing feature commits.
**Instead**: Report "修改已完成並通過驗證" and optionally ask "需要建立 commit 嗎?"

When the user does request a commit → load `references/commit.md` and follow it.

## Remote Directory Git Commands (mandatory)

Use `git -C <path>` instead of `cd <path> && git`. Chained `cd && git` may bypass the user's `Bash(git:*)` allowlist and trigger unnecessary permission prompts.
