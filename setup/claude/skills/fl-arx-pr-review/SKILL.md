---
name: fl-arx-pr-review
description: End-to-end in-session flow for reviewing one or more RELATED pull requests handed to you together — usually a coordinated change split across repos (e.g. several PR URLs pasted with review intent). Understands all the PRs as one picture FIRST (what each solves, the cross-repo topology, the shared contract, each PR's seam), then pre-flights and reviews each with that shared context, then gives one consolidated report — all in the current session so findings stay live for discussion. Trigger when handed multiple PRs to review, or a single PR that is one half of a multi-repo change. Read-only: never posts or edits. For ardge repos.
model: sonnet
---

# fl-arx-pr-review — ardge multi-PR Review Flow

A sequencer for reviewing one or more **related** PRs — typically a single change split
across repos (a proto PR + its consumer, a chart PR + its manifest, an RBAC grant + the
caller it unblocks). It composes the existing review skills in order, but adds the step
that isolated per-PR review misses: **understand all the PRs as one picture before
reviewing any of them.**

**Runs entirely in the CURRENT session — no fan-out to parallel agents.** Related PRs want
*shared* context, not fragmentation: the same reasoning that builds the cross-PR picture
then reviews each PR, so there is no information gap between "what is this whole change
doing" and "review this one file", no briefing to serialize across a spawn boundary, and
every finding stays in this session for your follow-up questions. (A fan-out agent buys
execution isolation and parallelism — neither of which helps a small set of *coordinated*
PRs in a session whose only job is this review.)

**Model note:** frontmatter pins `model: sonnet`, but that pin is not what this flow
costs. Because it runs in-session (above), the session model is what actually pays — a
2026-08 run of this flow logged `claude-opus-5` on every turn, including the one that
invoked the skill. The pin is `sonnet` rather than `haiku` for the subagent case: Step 1
here — cross-PR comprehension — is reasoning this orchestrator does *itself*, and there is
no reasoning-tier sub-skill to hand it to. A haiku briefing would be shallow and defeat
the point.

## When to run

- You are handed **more than one** PR to review, especially a coordinated multi-repo change.
- Or a single PR that is explicitly one seam of a larger cross-repo change.
- A lone standalone PR still works but gains little over reviewing it directly — the
  cross-PR value (Step 1, seam verdicts) is what earns this flow.

## Preconditions (check first)

```bash
python3 ~/.claude/skills/x-pr-review/scripts/pr-state.py --checks \
  <owner>/<repo>#<num> <owner>/<repo>#<num> ...     # all the PRs in one call
```

`--checks` 帶在這裡而不是留到最後:這條流程的產出是一份跨 PR 的合併判斷,而每支 PR 的 head CI 是那份判斷的輸入之一——描述寫的「測試全綠」講的是更早的 commit。它是同一次探測順手多印的,不是額外一輪。查不到時報 `CHECKS: unavailable` 而不是當成綠燈。

- Resolve each PR to `owner/repo#number`. If one won't resolve, the script says
  `VERDICT: unavailable` for that PR — stop and ask rather than reviewing the rest silently.
- The script takes the whole set in one call and reports each PR under its own `===` header,
  which is what retires the old hand-written loop: folding PRs into a shell `for` with
  `set -- $x` silently passed an empty PR number under zsh, which does not word-split
  unquoted variables.

### State gate — decide this BEFORE Step 1

A review only earns its keep on code that can still change. The script above answers this
outright on its `FROZEN:` line, which is this gate's own question — the two states it reports
`FROZEN: yes` for:

- **`STATE` is not `OPEN`** — the code is frozen; a gating review is moot.
- **`OPEN`, `ME_ENGAGED: yes`, `HEAD_CHANGED: no`, `REPLIES_AFTER_ME: 0`** — nothing new to
  act on.

Three of its other fields decide whether you should trust that line, and none of them is a
verdict:

- **`ENGAGED_EXCERPT`** — the first line of your last trace. `FROZEN: yes` off a drive-by
  question ("這個是基於哪個 branch？") means you are about to skip a review you never did.
  Read the excerpt; if it is not a review, treat the PR as un-engaged and say why.
- **`IS_DRAFT`** — `OPEN` and draft are compatible. A draft is live code, so the gate says
  proceed; whether reviewing it is premature is the user's call, so surface it.
- **`REVIEWED_SHA_REACHABLE: no`** — the commit you reviewed is gone (force-push), so an
  incremental re-review has no left side. That round has to be a full re-read; say so.

**Engagement is read from three buckets** — review bodies, issue comments, and inline review
comments — because the ardge convention for reviewing someone else's PR is **approve + recap
comment** (see `feedback_review_others_pr_no_self_comment`), so a prior review very often
lives in comments rather than reviews. An empty `reviews` array does **NOT** mean you haven't
reviewed this PR.

For any PR in those states, do **NOT** launch a gating review. **Stop and report** — per PR:
state, your prior verdict, last-activity date — and ask what the user wants:

1. **Retrospective read** — run Step 1 understand-all only, framed as comprehension /
   handoff (no findings posture, no `issue`/`nitpick`). Post-merge the cross-repo picture
   still has value; the gating review does not.
2. A **corrected PR set** (wrong or already-shipped URLs).
3. Nothing.

Proceed into the full flow (Steps 1–4) for PRs that are **`OPEN`** and either not yet engaged
by you (→ Step 3 dispatch picks 2a, first review) or engaged by you with author commits/replies
afterward (→ Step 3 dispatch picks 2b, reply-confirmation — confirm the author addressed your
earlier comments, a narrow check, not a re-review from scratch). **Let Step 3's `x-pr-review`
dispatch decide 2a vs 2b from the live `reviews`+`comments` probe — never pre-decide the case
here.** Pre-deciding 2a off an empty `reviews` array is the exact miss that turns a narrow
reply-confirmation into a wasteful full re-review. A mixed set is normal: short-circuit the
frozen ones, flow the live ones.

The probe you just ran looks like Step 3's dispatch and answers a different question. This
one is a **liveness gate** — can this code still change? — and reaching a case-shaped
conclusion here does not retire the Step 3 invoke. See Step 3 for what else that invoke
carries.

## The flow

### Step 1 — Understand-all (the anchor; do this before ANY finding)

Read every PR at **comprehension depth** — descriptions, linked issues, commit messages,
the diff *shape* (which files/areas, not line-by-line yet), and the product spec that governs
the change (see the `產品規格` bullet below for where it lives). Then state, as one briefing:

- **Per PR**: what problem it solves and why this approach — sourced from its description /
  issue, not guessed from the diff.
- **產品規格**: 每份 PR 各一列——規格的 `檔案:行` 加上整份規格的 GitHub 連結
  (`https://github.com/ardge-labs/ardge-project-issues/blob/main/<路徑>`,路徑中的空白寫成 `%20`),
  或「查過需求 repo,沒有對應規格」。空著
  就是這一步沒做,看得出來。判準是**這個改動有沒有使用者看得到的操作**,有就一定有規格;
  本 workspace 的需求 repo 是 `ardge-project-issues/`,分 `system-application/<app>/` 與
  `system-mechanism/`。這兩項寫在這裡是因為這一步就要用得到,而 `x-pr-review` 要到 Step 3
  才載入;引用規格的 finding 怎麼定級留給那支的 gate 第 7 關,這裡不重述。
- **The cross-repo picture** (this is what a per-PR reviewer can't see):
  - **Topology** — which repo plays which role, and the order things take effect. Draw it,
    don't narrate it: a producer serving two consumers has to show two branches, and prose
    lets that collapse into one chain. This drawing is what Step 3's path assertions are
    checked against, so it has to exist.
  - **Shared contract** — the concrete interface surface the PRs coordinate on: exact
    RPC / message / field / schema-key names, their types/values, and semantics. This is
    the source of truth every seam is checked against. When that contract IS a serialized
    format (config schema, proto wire, DB schema, API payload), render its before→after
    shape (old → new, minimal snippets) in the briefing — the format diff is what anchors
    every seam check. Whatever shapes you do render, open each with
    `<producer> → <consumer>`, and name in one line what the OUTERMOST consumer receives
    — one line each, not a paragraph. Without that label the reader assumes the names you
    showed are the outer ones.
  - **Seam responsibility per PR** — which boundary it sits on: *defines / implements /
    consumes / routes / grants*.
  - **當改動是「一個物件走過這些 repo」時,補一段那個物件的生命週期。** 一把金鑰、一份
    artifact、一個 token、一筆 event——用表格或編號逐步走完:哪一步在哪個 repo、產生什麼、
    這步之後手上有什麼。拓樸圖回答的是「repo 之間怎麼接」,回答不了「這個東西從哪來、經過
    誰、最後被誰用掉」,而後者才是不碰這個領域的讀者真正缺的。判準:briefing 裡出現了一個
    貫穿兩個以上 repo 的具體物件,就走一遍它的一生。

**Repo-local 詞彙在 briefing 第一次出現就要標歸屬**,寫成
`unwrap core`(arx-go-trust 的 `internal/trustd/unwrap.Core`,與 arx-platform-core 無關),
之後固定用同一個短稱。briefing 是整輪 review 的詞彙來源——這裡沒標清楚,後面每一則 finding
都繼承同一份歧義。完整判準與其他例子見 Step 3 載入的 `x-pr-review` output model——briefing 屬於內部報告,
所以那裡的第二類(作者在 code 裡自己取的名字)與「圖的節點與箭頭標籤要在圖之前有定義」同樣套用在
briefing 與它的拓樸圖上。

**Put this briefing in the same message the findings go in, right after the spec line — it is
Step 4's `Overall picture` slot: spec line, then briefing, then findings.** Aligning on the whole change
before findings is what removes the
information gap, and ordering within one message achieves it; stopping for a reply adds
nothing on top of that. **不要停下來等回覆**——稽核要一次比完、交出封閉清單,停一輪等回覆就違反這一點。For a single standalone PR
this collapses to ordinary per-PR comprehension.

### Step 2 — Pre-flight each PR

Invoke `arx-pr-pre-flight` per PR — it checks **only** PR metadata (reviewer / assignee /
labels, title, description), test completeness / over-testing, and doc sync. Consume its
findings.

**Ignore its `/x-pr-review` recommendation** — the review happens next, here, in this session.
Acting on it would double the review.

**Running a remote PR's tests (no local checkout).** Pre-flight's coverage gate wants tests
actually run, but a remote PR isn't checked out locally. One script extracts the head into a
temp tree, runs the command there, and removes the tree on exit — non-mutating, no worktree,
no branch switch. **It lives in `arx-pr-pre-flight`, which owns that gate; this flow calls it
by absolute path rather than keeping a second copy:**

```bash
~/.claude/skills/arx-pr-pre-flight/scripts/pr-head-tree.sh --repo <local repo path> --pr <num> \
  --subpath <chart/subdir> -- helm unittest .
```

`--repo` here is a **filesystem path**, not the `<owner>/<repo>` slug the `gh` commands above take — passing the slug gets `ERROR: cannot enter the --repo path`.

**Read its `VERDICT:` line, and treat `TREE INCOMPLETE` as `未驗` however the command exited.** The script fills each submodule from your local clone; one you never initialised stays an empty directory, so `ok` can mean the command simply never read through the gap, and `failed` can mean it died *on* the gap rather than on anything the PR did. Pre-flight's own Coverage rules cover both — the point here is that this flow reads the same verdict rather than assuming a zero exit means the suite ran.

`--subpath` sets the tool root, so pass the chart's own directory for `helm unittest` and omit
it for `go build ./...` (which needs `go.mod` at the top of the extracted tree). The tool
decides which root it wants; neither form is the default. Everything after `--` runs with **cwd
at that root** — which is why `helm unittest .` above resolves to the chart.

This is only needed to *execute* something. Reviewing a remote PR's code needs no tree —
`x-code-review` reads that from the fetched refs (Step 3).

### Step 3 — Review each PR in-session

**Invoke `x-pr-review`.** The invoke does two jobs, and knowing the answer to the first one
does not excuse skipping it.

**Job 1 — dispatch picks the case per PR.** Let **its Step 0 dispatch** decide; do NOT
pre-decide it's Case 2a. Dispatch probes each PR (author + whether *you* already left a
review/comment on it) and selects Case 1 / 2a / 2b. This is load-bearing because a review
is typically run in a **fresh session with no memory of an earlier review you left** — so
the only signal that this is a **reply-confirmation (2b: confirm the author addressed your
earlier comments)** rather than a **first review (2a)** lives on the PR, not in the prompt.
Hard-coding 2a re-reviews from scratch a PR where you should instead be checking the
author's responses — a different, narrower procedure. When PRs in the set land in different
cases, run each under its own case.

**Job 2 — the invoke is what puts the output model and posting skeleton in context.**
`x-pr-review`'s SKILL.md carries the finding-atom shape, the icon↔label map, and Templates
A / C inline, deliberately, so that posting later needs no reload step. That design only
pays off if the invoke actually happens. **So run it even when the Preconditions probe
already told you the case** — "I know it's 2a, the invoke is redundant" is the failure
mode, and it fails silently: nothing breaks until Step 4, where you shape findings ad-hoc
because the model was never loaded, and the user has to ask for the format.

Then follow that case's discipline in full: baseline from source (`git show <ref>:<path>`,
never the working tree), comprehension, design critique, the pre-finding verification gate,
severity calibration. **Read-only throughout.** Correctness/security **is delegated to `x-code-review`
for every PR that has a local clone AND clears that skill's size gate** — `< 50 lines and ≤ 3 files`
does not get a deep correctness pass unless the diff carries non-trivial new logic. Both conditions
belong in this sentence rather than one of them living in the delegation rule downstream: an agent
reading top-down acts on the last thing it read, so a universal "delegate for every PR" here spawns a
full correctness pass on a three-line chart-value change.

Its `A..B` range parameter takes the fetched base/head ref pair directly, so the PR head never has to
be checked out, and it runs read-only in that mode (no auto-fix offer). Compose each invocation per
`x-pr-review`'s four rules for it (head-side ref choice, three dots, cwd, fork heads), and launch it
by that skill's timing rule: as soon as you can write the prompt's scrutiny list for that PR, before
your own design critique of it — never right after the fetch with an empty list.

**One invocation per PR, each naming that PR's own repo.** This is the step this flow is most
likely to get wrong, because its whole premise is multi-repo: `x-code-review` decides
single-project vs cross-repo by counting repos in the working directory, so a range supplied from
a directory that holds all the PRs' repos comes back as `VERDICT: error` (exit 1) with the
candidate repos listed. **Answer it with `--repo <that PR's repo path>`** — that flag is the only
resolution, since neither the refs nor the branch name identify a repo. Never batch the set into
one cross-repo invocation: Step 1X derives its own `BASE...HEAD` per project, which would review
code no PR in this set changed.

Inline correctness is the fallback for a repo with **no** local clone, and `x-pr-review`'s baseline
step normally removes even that case by cloning. That step announces the clone rather than asking,
so "the user declined" is not a state this procedure produces — reach for inline only when the clone
itself is impossible (no network, no access to a private repo, the server refuses the partial-clone
filter), and say which.

Carry the Step 1 cross-PR context into each PR's review — this is the seam check isolated
review misses:

- **Seam verdict** — does this PR's boundary hold against the shared contract AND the one
  sibling source it actually touches? Pull only that sibling file/symbol, not the whole
  sibling repo: an RBAC PR reads the consumer's call to confirm the granted verb; a routing
  PR reads the registered path. **Name any drift and cite BOTH sides' `file:line`.** For a
  standalone PR the seam is just this PR honoring its own repo's contract and passing
  parameters correctly to what it calls.
- **Path assertions trace to the Step 1 topology.** A finding that places interfaces on a
  shared path — "upstream", "downstream", "the same chain", "上游" — must correspond to one
  branch of the drawing. Interfaces hanging off different branches of the same producer are
  parallel surfaces, not hops on one chain: say so and give each its role. Naming the
  interfaces is not enough on its own — an enumerated pair still carries whatever relation
  the modifier in front of it claims, and that modifier is where a two-branch topology gets
  flattened into one.
- **Calibrate depth to HAND-WRITTEN change size** — `pr-size.sh --repo <path> --range
  <base>...<head>` gives that figure with generated and lock files excluded per file and a
  reason for each exclusion. Small single-purpose diff → a clean verdict with 0 findings is a
  valid, healthy outcome; don't manufacture nits to look thorough.
- **High-risk override** — cluster microservices, shared Go libraries, public API contract
  changes, DB schema / migrations get full design critique regardless of line count;
  surface affected callers and backward-compat concerns.
- **Generated files** — do NOT review their content. Confirm only that they were
  regenerated when their source changed and not hand-edited, via a cheap check (does the
  new symbol appear? is the generator pinned to a released tag?). Don't full-read them.

**Context safety valve.** This session has no auto-compact, so a very large combined diff
can wall the context. If that risk is real, delegate the *single heaviest* PR's correctness
deep-read to a sub-agent (`Agent`, read-only) so its code reads stay out of this session —
brief it with `model: sonnet` to invoke `x-code-review`, run its Step 0 and Step 2 itself without
spawning another agent (the item 1 `x-coding-standards` load included), and return its Step 3 output
verbatim, Coverage / Fixed / independence lines included —
but keep Step 1, the seam checks, and the report in-session. Reach for this only under real
pressure; the default is fully in-session.

### Step 4 — Consolidated report

Render per **`x-pr-review`'s output model** (理解 + finding atoms + clean handling + 繁體中文
with engineering-standard vocab + diagrams only where order/timing makes a finding hard).
For multiple PRs, structure it:

0. **規格出處** — 報告第一行。照抄 Step 1 產品規格列的連結,寫成「這組 PR 對應 <規格名> — <連結>」;
   對應多份規格就一份一行,沒有對應規格就照抄「查過需求 repo,沒有對應規格」。
1. **Overall picture** — the Step 1 briefing, verbatim or tightened: topology, shared contract, the product-spec anchor, the object's lifecycle, timing. This slot is where that briefing lands, which is why Step 1 does not emit it on its own; do not write a second, narrower version here.
2. **Seam verdicts** — the core; each cites both sides' `file:line`.
3. **Per-PR sections** — one per PR, headed by `repo#number`.

Findings stay in this session — the user typically asks follow-up questions, so keep the
evidence live rather than closing with a static hand-off.

**Posting is never automatic.** Only when the user explicitly asks to comment do you post,
via `gh pr review` / `gh pr comment` — a separate step the user triggers. You start from the
skeleton already in context from Step 3's invoke rather than from zero, then read
`x-pr-review`'s `references/publish-format.md` before posting for the detail layer (render
hygiene, full Template B, multi-round composition).

**Routing findings across PRs.** The in-session report is one piece; the posts are not.
Decide placement per finding, and say the placement out loud before posting so the user can
redirect:

- A finding goes on **the PR whose `file:line` it cites** — that is where the author opens
  the code.
- A finding whose resolution depends on a sibling PR goes on **the PR that would actually
  change**, written as contingent and naming the sibling — e.g. a contract-level question
  posted on the proto PR as 「看 `<consumer>#<n>` 那邊怎麼決定」 with both branches spelled
  out. Cross-reference the sibling; do not post the same point there too.
- **One finding, one comment.** Repeating a point across PRs inflates the set — the author
  reads all of them.
- A PR in the set with nothing actionable still gets a short comment when you are its
  requested reviewer. Silence on an assigned PR is indistinguishable from not having looked.

## Outward-action checkpoints

Posting a review or comment (after Step 4) is the only **outward** action, and it is
user-triggered — never automatic. The Step 1 briefing is **not** a checkpoint: it leads the
same message the findings go in, so nothing waits on a reply. (The Preconditions state gate
does stop and ask, but that is a liveness question about whether to review at all, not an
action taken on the PR.)

## What this flow does NOT do

- **No fan-out** to parallel per-PR agents — related PRs want one shared context.
- It does not post or edit on its own initiative — posting is user-triggered, after Step 4.
- It does not run correctness itself when the repo is cloned locally — that goes to
  `x-code-review` on the fetched range (Step 3), with each side chosen per
  `x-pr-review`'s rules rather than hardcoded to `origin/…`: a local branch wins on the
  head side, and a fork PR's head is `pr-<num>`. Inline correctness is only for a repo
  with no clone.
- It does not re-run the review at pre-flight (Step 2 metadata ≠ Step 3 review).
