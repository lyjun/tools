---
name: fl-arx-pr-ship
description: End-to-end flow for shipping your own ardge PR — drives self-review and cleanup, commit/squash, PR creation, a metadata/test/doc hygiene gate, revision, and a final description-sync check in one ordered pass, pausing at every outward action. Trigger when you have local changes on a feature branch and want to take them all the way to a submitted ardge PR (e.g. "發 PR", "幫我走完發 PR 流程", "/fl-arx-pr-ship"). For ardge repos following the Git Flow + hygiene-gate conventions.
model: haiku
---

# fl-arx-pr-ship — ardge PR Ship Flow

A sequencer that takes a feature branch from "my changes are local" to "PR submitted with
a description that matches it", by composing the existing PR skills in order. This skill does **not**
review, fix, or commit on its own — each heavy step is delegated to a dedicated skill
that runs at its own model. The orchestrator's only jobs are: run the steps in order,
relay each skill's output, and **stop at every outward action for user confirmation**.

**Model note:** frontmatter pins `model: haiku` — sequencing + report relaying needs no deep
reasoning (the reasoning lives inside the delegated skills). Whether that pin is what this
flow costs depends on how the skill was invoked; which invocation paths honor it is
`x-cc-config-guide`'s to state (〈Skill model 與 effort 的實際效力〉), not this file's — read
it there before making a cost decision. The savings this pattern does deliver come from the
delegated skills' own `Agent(model: ...)` calls, which are a separate mechanism and do take
effect.

## When to run

- You have local changes on a `feature/*` (or `release/*` / `hotfix/*`) branch and want
  to ship a PR end to end. Usually invoked explicitly via `/fl-arx-pr-ship`.

## Preconditions (check first, bail early)

```bash
git branch --show-current
git status --porcelain
```

- If on `develop` / `main` / `master` / `release/*` (a protected base) → **stop**; this
  flow ships a feature branch, not the base.
- An empty branch (no commits ahead of base) → **stop**; nothing to ship.

## The flow

### Step 0 — Self-review + cleanup

Invoke the unified self-review skill (`x-pr-review`). On your own pre-PR branch it
auto-selects self-review mode, which **already** runs correctness/security review *and*
applies cleanup fixes internally. Do **not** also invoke the cleanup skill here — that
would double the cleanup pass.

Two distinct outputs to handle:
- **Correctness/security report** — findings only, *not* auto-fixed. Present it; let the
  user decide what to fix.
- **Cleanup fixes** — applied to the working tree but left **uncommitted** by design.

**CHECKPOINT:** surface the correctness report and the applied cleanup before moving on.

### Step 1 — Commit / squash the review output  ← required bridge

Step 0 leaves the tree dirty (cleanup fixes + whatever correctness fixes the user made),
and `arx-create-pr` refuses to run with uncommitted changes. So commit before creating.

Invoke `x-git-ops` to commit — it owns commit-message conventions; never hand-write
`git commit -m`. This is also the natural squash point: your dev rhythm (many WIP commits)
plus the review fixes tend to pile up, so squash into clean logical commits here. (`arx-create-pr`
re-checks and nudges squash if commits still exceed 5 — a backstop, not the primary gate.)

**CHECKPOINT:** confirm the commit/squash plan before it runs.

#### Mark the reviewed commit

Once the commit lands, mark it — this is the commit whose code Step 0 actually read:

```bash
git update-ref refs/arx-ship/reviewed HEAD
git rev-parse --short refs/arx-ship/reviewed   # echo it so the user sees what was marked
```

Mark it **unconditionally**, including the case where Step 0 applied no cleanup and the
user fixed nothing, so no new commit exists — then the mark is simply the current HEAD.
A missing mark does not fail loudly; it makes every later check trivially pass, which is
the failure mode this whole mechanism exists to prevent.

Use a git ref, not a conversation note or a shell variable. Shell state does not survive
between Bash calls, and a SHA pasted from conversation is one transcription away from
`git diff ..HEAD`, which git reads as `HEAD..HEAD` — empty output, exit 0, silent pass.
A ref is readable by every later command without anyone re-typing anything.

`update-ref` overwrites unconditionally, and Step 1 is a required bridge that every later
check sits behind — so a ref left over from a run that died partway cannot leak into the
next run. Deleting it at the end (Step 5) is hygiene, not a load-bearing step.

#### The delta check (used by Steps 2, 3, 4)

Two commands, in this order. The first exists because `rebase` / `squash` / `amend` all
move HEAD off the marked commit, and nobody should have to *remember* that they just did
one — the check reports it:

```bash
git merge-base --is-ancestor refs/arx-ship/reviewed HEAD && echo IN-HISTORY || echo REWRITTEN
```

- **REWRITTEN** — history was rewritten since the mark, so the marked commit is no longer
  in HEAD's ancestry and any diff against it would be meaningless. Do not diff. Instead
  decide what the rewrite did:
  - Content unchanged (squashing already-reviewed commits, an amend that only edits the
    message, a clean rebase onto a moved base) → re-mark HEAD and carry on.
  - Content changed (a rebase where you resolved conflicts, an amend that edits code) →
    that content is unreviewed. Review `origin/<base>...HEAD`, then re-mark HEAD.

  The common case is not a rewrite you ran yourself: `arx-create-pr`'s base-sync at Step 2
  offers to run `git rebase origin/$BASE`. This check is what catches it.

- **IN-HISTORY** — the mark is still meaningful, so run the diff:

  ```bash
  git diff --name-only refs/arx-ship/reviewed..HEAD -- ':/' \
    ':!*_test.go' ':!*_test.ts' ':!*.test.*' ':!*.md' ':!docs/**'
  ```

  `':/'` anchors the pathspec at the repo root; a bare `.` is relative to cwd, so running
  this from a subdirectory would silently report "no code changed". Test and doc paths are
  excluded because the hygiene gate at Step 3 owns them.

  - **Empty** — the code is identical to what Step 0 read. Whatever review nudge you are
    looking at is redundant; suppress it.
  - **Non-empty** — those files entered *after* the review. Invoke the `x-code-review`
    skill with `refs/arx-ship/reviewed..HEAD` as its argument, then re-mark HEAD.

    `x-code-review` rather than `x-pr-review` here, even though pre-flight's report points
    at the latter: a top-up needs correctness/security on the new files only. Running the
    full `x-pr-review` would take Case 1 and re-run `x-code-improvement`, whose cleanup
    Step 0 already applied to this tree.

    Invoke it by that exact skill name. Typing `/code-review` reaches a different, built-in
    review command whose arguments and output shape are not the ones described here.

    Passing the ref name is safe even though `x-code-review` rewrites a supplied `A..B`
    into three-dot `A...B`: this branch only runs when the ancestry test said IN-HISTORY,
    which means `merge-base(ref, HEAD) == ref` and the two forms select the same commits.

**Which invocation form to use.** `x-code-review` takes no range (auto-detect), `full`, or
an explicit `A..B`. This flow uses two of them, at different points:

- **Step 0's first review** — no range. `x-pr-review` delegates without one and gets full
  `BASE...HEAD`, which is what a first review should read.
- **A delta top-up** — explicit `refs/arx-ship/reviewed..HEAD`, never bare. Auto-detection keys its
  incremental mode off GitHub review records, and on your own PR it looks for the latest
  review *by someone else* — on a fresh solo PR that does not exist, so it falls back to
  full `BASE...HEAD` and re-reviews everything. That is the duplication this check exists
  to avoid.

### Step 2 — Create the PR

Invoke `arx-create-pr`. It handles base-sync, quality gates (`lint` / `test` / `build` /
`docs`), the squash backstop, description drafting, push, and `gh pr create`.

Its base-sync check may rebase the branch onto the updated base. You do not have to track
that — the delta check's first command reports `REWRITTEN` when it happens.

**Its "建議先跑 `/x-code-review` 與 `/x-code-improvement`" nudge is conditional — run the
delta check before deciding.** The nudge is conditioned on "若尚未審視變更", and whether that
is false depends on the code, not on which step you are standing in. The common case that
makes it true again: `make lint` or `make test` fails inside this step, you fix the code,
and that fix is now in HEAD without anyone having read it.

**CHECKPOINT:** review the drafted title and description before it pushes/creates — this
is an outward action.

### Step 3 — Pre-flight hygiene gate

Invoke `arx-pr-pre-flight` on the new PR. It checks **only** PR metadata, test
completeness, and doc sync — it is **not** a code review.

**Run the delta check when you consume the report** — not only when pre-flight prints its
closing `/x-pr-review <num>` recommendation. Any ❌ item suppresses that line — `block`,
and Phase 1's `fail:` — so
waiting for it means the one path where code is most likely to be unreviewed is also the
path where nothing prompts you to look.

That recommendation is aimed at reviewing someone else's PR; on your own PR it resolves to
self-review, which Step 0 already ran. The delta check is what decides whether any of it
needs redoing.

Empty means the deep review at Step 0 still covers HEAD, and the recommendation (if
printed) is pure duplication. Non-empty means code arrived after that review, and
re-reviewing those files is required whether or not pre-flight asked for it.

Consume its metadata/test/doc findings either way.

### Step 4 — Revise (only if pre-flight's 判定 is ❌)

If pre-flight's 判定 is ✅, **skip this step** — including a ✅ that carries a `note:` or
`未驗:`, since neither is a finding to fix here.

Key the entry on the ❌ count, not on the word `block`. Pre-flight writes its Phase 1
metadata findings as `fail:`, which counts toward ❌ and suppresses the recommendation
exactly as `block` does — and those are the title / label / description findings the
routing below hands straight back to the gate, so a `fail:`-only report is the one this
step most needs to catch.

Otherwise the ❌ items are hygiene (title / labels / tests / docs), not code review.

**This orchestrator does not fix anything itself** — route each finding to its owner:
- **Title / labels / PR body** — the hygiene gate applies these on explicit opt-in; let it.
- **Tests / docs / code** — the user fixes these (the gate deliberately won't). When the
  fix dirties the tree, commit it via `x-git-ops` (same discipline as Step 1 — never
  hand-write the commit), then push with `--force-with-lease`.

If a fix changes code and you force-push, **sync the PR description to match** with the
push — a stale description drifts the PR from its code.

**CHECKPOINT:** confirm before any force-push.

After revising, two things must come back clean before moving on. **Clean means the gate's
判定 is ✅** — a `note:` or `未驗:` line carried into that ✅ does not hold this step open,
because both report something this PR cannot act on and re-running changes neither.

1. **Re-run the Step 3 hygiene gate** — a force-push can open new hygiene gaps.
2. **Run the delta check** — this step is where code most often changes after the review,
   because the gate deliberately hands test/doc/code fixes back to the user, and the fix
   commonly lands as an amend plus force-push. Re-review and re-mark per the check's verdict.

### Step 5 — Description sync check

The PR description is the only prose artifact this flow produces, so if it does not match
HEAD, the PR has no accurate account of itself anywhere.

```bash
gh pr view --json body --jq .body
BASE=$(gh pr view --json baseRefName --jq .baseRefName)
git fetch origin "$BASE" --quiet
git diff --stat "origin/$BASE...HEAD"
```

Confirm the description still covers what shipped — every Step 4 revision, and every commit
added after the description was drafted. If the change touches call order, pipeline
composition, cross-subsystem data flow, or a state machine, its 流程 / 架構變更 section must
exist and match the shipped code; `arx-create-pr` owns that section's format and trigger
conditions.

Update via `gh pr edit --body-file` when it has drifted.

**CHECKPOINT:** show the before/after of the description body before editing.

Then delete the review mark:

```bash
git update-ref -d refs/arx-ship/reviewed
```

## Outward-action checkpoints (never auto-proceed past these)

| Action | Step |
|--------|------|
| commit / squash | 1 |
| push + create PR | 2 |
| force-push | 4 |
| edit PR description | 5 |

## What this skill does NOT do

- It does not review, edit, commit, or post anything itself — those belong to the
  delegated skills above.
- It does not re-review code it has already reviewed. "Already reviewed" means reachable
  from `refs/arx-ship/reviewed`, not "we are past Step 0" — code that arrives after the mark
  still gets reviewed, and that is what the delta check is for.
- It does not ask anyone to remember that a rebase or squash happened. The delta check's
  ancestry test reports it.
- It does not skip a checkpoint to "save a round"; outward actions always pause.
