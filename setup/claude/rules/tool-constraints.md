# Tool Constraints

Constraints Claude Code must follow when using tools — violations cause stuck state, lost output, or silently wrong data.

## Bash: Use `;` for Independent Fallible Commands

When a single Bash call contains multiple **independent** commands where any one may fail (e.g., `gh api` queries for repos that may return 404, health checks, optional lookups), use `;` instead of `&&` to prevent cascade failures.

- `&&` → stops at first non-zero exit, so the later independent commands silently never run and you lose their output
- `;` → runs all commands regardless of exit codes

Only use `&&` when later commands genuinely depend on earlier success.

## Bash: No Associative Arrays Inside `bash -c`

The Bash tool's own shell is zsh 5.9, where `declare -A` works — plain tool calls are fine.

Inside `bash -c` or a `#!/bin/bash` script it is not. This machine's `/bin/bash` is 3.2.57: `declare -A` errors, then assignment silently degrades to an indexed array, so `n[foo]=1; n[bar]=2` yields `foo=2 bar=2 count=1` — both keys collapse into index 0.

For key-value mappings inside a bash script, use explicit per-item statements or Python.

## Bash: No `timeout` on macOS, and Piping Destroys the Exit Code

Two ways a build/test command reports success without having run. Both hit in one call:

`go build ./... 2>&1 | tail -20; echo "exit=$?"` printed `exit=0` while the build never executed — `timeout 480 go build` had failed with `zsh: command not found: timeout` (macOS ships no `timeout`; coreutils installs it as `gtimeout`), and `$?` belonged to `tail`, not to the pipeline's first command.

Run the command bare, redirect to a file, take `$?` on its own line, then read the file:

```bash
go build ./... > /tmp/build.log 2>&1; echo "exit=$?"; tail -15 /tmp/build.log
```

Never pipe a command whose exit code you are about to test. `PIPESTATUS`/`pipestatus` exist but differ between bash and zsh — the redirect avoids the question.

## Bash: zsh Does Not Word-Split Unquoted Variables

`for p in "repo 104"; do set -- $p; gh pr view "$2" --repo "$1"; done` works in bash and silently breaks in zsh: `$1` becomes the whole `"repo 104"` string and `$2` is **empty**. The failure does not name the empty argument — `gh pr view ""` falls back to resolving the current branch, so it reports `could not determine current branch: fatal: not a git repository`, which reads as a cwd problem in a directory that is genuinely not a repo.

Never pack multiple fields into one loop item. Write one explicit command per item, or use two parallel arrays, or `read a b <<< "$line"`. zsh's explicit split is `${=p}` if a split is truly wanted.

## Bash: zsh Aborts on Unquoted `?` and `*` — gh api URLs Are the Common Case

`gh api repos/o/r/contents/x/action.yml?ref=v1` never runs: zsh treats `?` as a single-character glob, finds no matching file, and with its default `NOMATCH` **aborts the command** rather than passing the literal — `(eval):4: no matches found: repos/...?ref=v1`. The tool reports a shell error, so it reads as a malformed path rather than a quoting bug.

Quote every `gh api` path that carries a query string: `gh api "repos/o/r/contents/x/action.yml?ref=v1"`. Same for any argument containing `?`, `*`, `[`, or `{`.

Two arguments are quoted unconditionally, whatever they contain: the value of `--include=` (`grep -rn x --include='*.go'`) and the argument to `--jq` (`--jq '.headRefOid[0:8]'`). Both routinely carry a glob or a bracket, and in one session (2026-10-16) each was written bare and aborted the command.

## Bash: zsh Aborts the Rest of the Call on a Word Starting With `=`

`echo a; echo ====; echo b` prints `a`, then `(eval):1: === not found`, and stops — `b` never prints and the call exits 1. zsh reads a leading `=` as `=cmd` (expand to the command's path), finds no command `===`, and aborts **everything after it in the call** — later `;`-joined commands and later lines alike; only a `( … )` subshell contains it. Used as a section separator between reads, it silently drops every read after it, and the error reads as one of those reads failing.

The same trap fires on `[ "$a" == "$b" ]`: `==` is a word starting with `=`, so it dies with `= not found`.

Write separators as `echo '---'`, use `=` (not `==`) inside `[ ]`, and quote any other argument that starts with `=`.

## Bash: zsh Eats the First Letter After `$VAR:`

The Bash tool's shell is zsh, which parses the letter right after `$VAR:` as a history modifier and consumes it. `git show $H:rootfs/x` expands to `...xootfs/x` — the `r` is gone, so the failure reads as a typo in the path rather than a quoting bug; `$H:src/x` dies with `bad substitution` instead (`r h t e` confirmed eaten, `s` errors). `$H:docs/x` and `$H:main` are untouched, which is what makes this look intermittent.

Write `"${H}:rootfs/x"`. The braces are the fix — quoting alone does not help.

## Git: An Empty Range Side Is Substituted With HEAD, at Exit 0

`git diff --name-only "...HEAD"` returns **exit 0, empty stdout, and empty stderr** — measured. git substitutes HEAD for the missing left side, so the range compares HEAD against itself. Every signal says success and the empty output reads as "nothing changed", which is why testing `$?` does not catch it: this one is not a failure, it is a different question answered.

The same substitution silently re-injects the local checkout into a range meant to compare two remote refs, so a review running on `"$BASE...HEAD"` with `BASE` unset reports a clean branch that has unreviewed commits.

Validate the range's shape before handing it to git: it must contain `...`, and neither side may be empty. A bad ref is the easy half (`git diff` exits 128 with empty stdout there, so `$?` finds it); an empty side has to be rejected before the call.

## gh: `reviewRequests` Empties Itself Once a Review Lands

`gh pr view <n> --json reviewRequests` lists only the **pending** requests. GitHub deletes the request the moment that person submits a review, so a PR that already carries a review returns `reviewRequests: []` while its GitHub sidebar still lists that reviewer. Measured: a PR with two submitted reviews from one account reported `reviewRequests: []` and `reviews` of length 2.

Nothing errors and the empty array is well-formed, so `[]` reads as "no reviewer assigned" — wrong on exactly the PRs furthest along, and on a re-review round that is every PR in front of you. The REST field `requested_reviewers` behaves identically.

Never ask for `reviewRequests` alone: write `--json reviewRequests,reviews` and treat a non-empty `reviews` as assigned. Both fields are valid on `gh pr list --json` too.

## Agent: A `fork` Subagent Ignores the `model` Parameter

`Agent(subagent_type: "fork", model: "haiku")` does not run on haiku. A fork inherits the parent's conversation **and** the parent's model; the `model` argument is dropped with no error and no notice, so the spawn that was meant to be cheap bills at the parent's rate — Opus here.

This is the Agent tool's `model` **parameter** only. A skill's frontmatter `model:` under `context: fork` is a different mechanism and is honored: it sets the forked subagent's model. Conflating the two is what makes the drop look impossible.

Never pass `model` to a fork expecting a downgrade. When the point of delegating is a cheaper model, spawn a fresh agent (`general-purpose`, `Explore`, …) with an explicit `model` and brief it, and accept paying to re-establish the context a fork would have inherited free.

## Bash: `>/dev/null` on a State-Changing Command Deletes the Only Post-Mortem

A script ran `netplan generate >/dev/null 2>&1` then `netplan apply >/dev/null 2>&1` — the motive was clean output, keeping only the few lines being looked for. The machine went offline during `apply` and the failure point is still unknown: whether `generate` complained about the YAML, what `apply` returned, none of it exists anywhere. The incident degraded from "next time avoid X" to "never run that command", because there is no X.

The stop condition is: **when this step fails, a record of why survives on the machine and can be read afterwards.** The default way to get there is to redirect to a file and take `$?` on its own line — `<cmd> >"$LOG" 2>&1; echo "exit=$?"`, then `tail -20 "$LOG"` — but the recipe is not the rule. Never reuse a fixed path: a root-owned stale `/tmp/<step>.log` from an earlier run makes the redirect fail to open, and when `>` cannot open the file **the command never runs at all**, so the record and the action are lost together. Use `LOG=/tmp/<step>.$$.log` or a timestamp, on a path this account can write.

Noisy output is a formatting problem — solve it with `tail`, not by discarding. Pure queries (`ip -br addr`, `cat /sys/...`) are exempt: re-running them costs nothing.

This compounds with the pipeline trap above — `<cmd> 2>&1 | tail; echo $?` both discards the log and reports `tail`'s exit code.

## Git: Restore a Deliberately Broken File on the Host, Not Inside the Container

Why the container half is the wrong place: a restore that fails there fails *quietly enough to miss* — the broken file simply stays broken in the working tree while the session moves on. In a worktree the container half does not merely risk failing, it cannot work at all: the worktree's `.git` points outside every devcontainer mount, so each git command that needs the repo dies there — the main repo's own tracked files included, not just the submodule ones. Mechanism and the measurements live in `~/.claude/skills/x-environments/references/devcontainer.md`, 〈Worktree 的 container 內不能跑 git〉. The host is the only place the restore can happen.

Break and restore both on the **host** with git (`git stash`, `git checkout -- <path>`), never by editing the change back out. Break with a whole-file replacement or `git apply`; a `sed` pattern that matches in more than one place restores incompletely and leaves residue nobody notices, because the file still looks plausible.

Two checks, both required, and both **scoped to the broken path** — an unscoped check never comes back clean, because the branch's own uncommitted work is sitting in the same tree: `git status --porcelain -- <path>` empty **and** `git diff <pre-break ref> -- <path>` empty. A restore that satisfies only the first has re-introduced content under a different shape.
