# Baseline 建立的執行細節

`SKILL.md` 的〈Mandatory pre-step: establish baseline〉決定**要做什麼**與**在哪個 ref 上讀**;這份檔是那兩件事的執行細節,原文搬過來——`origin/<head>` 解析不出來時改用哪個 fetch 形式,以及本機沒有 clone 時怎麼 clone。開始建 baseline 之前讀完這份。

## Fetching the head when `origin/<head>` does not resolve

**That fetch form fails in two cases, not one:** a fork PR (the head is not a branch on the
base remote) and **any PR whose branch was already deleted** — this workspace merges with
`--delete-branch`, so every merged PR is in that state. `pull/<num>/head` covers all three,
so prefer it whenever `origin/<head>` does not resolve. Check first — `gh pr view <num> --json headRepositoryOwner,headRefName` — and when the owner differs from the repo's, fetch the pull ref into a local branch instead and use **that** name as `<head>` everywhere below:

```bash
git fetch origin "pull/<num>/head:pr-<num>"    # then <head> is pr-<num>
```

This has to be settled in step 1, not later: everything in step 2 reads at `<head>`, so a `<head>` that does not resolve takes the whole baseline with it.

## Cloning when the repo has no local clone at all

Reading at a ref assumes one exists — `git show` has nothing to run against. Clone it,
announce that you did, and then apply the ref-reading rule and the base/head ref choice
unchanged. This is one of the skill's two writes — the other is the `pr-<num>` fetch above,
which lands inside an existing clone — and nothing else here edits anything (the read-only
guarantee is about the code under review — no commits, no pushes, no edits to any repo's
contents).

```bash
# <workspace> = the SHARED repo directory. Derive it from a repo that is a direct child
# of it, never from one inside a task/worktree directory — the parent of
# <ws>/worktree/issue-x/<repo> is the single-repo directory the rule below forbids.
# Pick the candidate with the most sibling repos:
#   for d in <candidate dirs>; do echo "$(ls -d "$d"/*/.git 2>/dev/null | wc -l) $d"; done | sort -rn | head -1
git clone --filter=blob:none git@github.com:<owner>/<repo>.git <workspace>/<repo>
# Every later git call must target it explicitly — cloning does not change cwd:
#   git -C <workspace>/<repo> show <ref>:<path>
```

**Ask the user for the workspace path when no repo is available to derive it from.** This branch fires precisely when the repo is missing, so "the parent of a known repo's toplevel" has nothing to measure if the session holds no repo at all. One question beats cloning into an arbitrary directory.

**`git -C <workspace>/<repo>`, not a bare `git`.** The clone leaves cwd where it was, so the baseline rules in `SKILL.md` — written as bare `git show <ref>:<path>` — would run in the old directory and fail, or succeed against a different repo. Carry the path into every read, and into the range you hand `x-code-review` (its `<path> A..B` form exists for this).

**Not `--depth 1`.** A three-dot diff has to compute the merge-base, and a shallow clone
carries no history to compute it from. `--filter=blob:none` keeps the full commit graph
and defers file contents until something reads them — so `git blame` over history still
works but fetches blob-by-blob, which needs the network and is slow on a long file.

**Clone into the shared workspace, never into a task directory that currently holds one
repo.** `x-code-review` decides single-project vs cross-repo by counting repos in the
working directory, so a second checkout appearing there silently flips every later run in
that directory to cross-repo mode — where a range comes back as `VERDICT: error` and the run
cannot proceed without naming the repo with `--repo`.

**If the clone fails** (no network, no access to a private repo, the server refuses the
partial-clone filter): say which, then fall back to reading through
`gh api repos/<owner>/<repo>/contents/<path>?ref=<sha>` — and state in the report that
coverage is degraded, because the coverage list's `讀過` disposition now costs one API
call per file with no grep and no caller search. **A clean verdict is not available on a
fallback run.** Do not silently substitute the fallback for a clone that would have
worked.

The alternative — reading the PR file by file through `gh api contents?ref=<sha>` — is
what this rule exists to prevent. One call per file, no grep, no sibling browsing, no
caller search: coverage collapses to whatever you happened to open, which is the
mechanism behind a clean verdict issued off a fifth of the diff. Cloning costs one
command and every rule in this skill then works as written.
