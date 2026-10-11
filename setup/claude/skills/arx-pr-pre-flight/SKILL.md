---
name: arx-pr-pre-flight
description: Use before running a deep code review on a PR. Checks PR metadata (reviewer/assignee/labels, title, description), test completeness/over-testing, and documentation sync, then gates whether the PR is ready for a deep code review. Trigger on phrases like "pre-flight PR 123", "review 前先檢查 PR #456", "PR pre-check", "準備 review PR XXX", or whenever the user wants a structured pre-review pass before reviewing the code itself. Designed to suppress manufactured nits — empty findings are a valid and preferred outcome.
model: sonnet
---

# ARX PR Pre-Flight Skill

A pre-flight checklist that runs **before** the deep code review. It gates three areas — PR metadata, tests, and docs — and recommends moving on to `x-pr-review` only when those gates pass.

`x-pr-review` is the target because it is the one that takes a PR number: it dispatches on ownership and runs the full review for someone else's PR (its Case 2a), delegating correctness/security downstream.

This skill is intentionally **opinionated about restraint**. Manufactured nits are a failure mode; an empty findings section is a valid and preferred outcome.

---

## Review Discipline (Read This First — Applies to Every Phase)

These rules override the natural impulse to "produce a list of findings." Follow them in every phase below.

1. **No-issue is a valid outcome.** If a phase finds nothing real, write `沒看到要改的地方` and move on. Do NOT scan for subjective preferences (wording, ordering, cosmetic taste) to fill the section.

2. **Nit definition is narrow.** A real nit is one of:
   - Typo or grammatical error in code/docs.
   - Naming that violates a project convention documented in CLAUDE.md or a linter rule.
   - Style inconsistency with **immediately surrounding code** (not "I would write it differently").
   - A small change with an objectively correct answer.

   "I think X reads better" is **not** a nit. Description wording, table column order, comment phrasing, and similar preferences are out of scope.

3. **Form a position before suggesting.** Before raising an item, you must be able to state in one sentence: *what invariant or user-visible behavior this protects, and what breaks if we don't fix it.* If you cannot, drop the item — do not surface it as "trade-off, your call." Outsourcing the decision is a tell that you have not done the thinking.

4. **Test suggestions need a protected invariant.** Before suggesting "add a test," answer: *which invariant or behavioral contract does this test pin?* If the answer is "pin a library's default behavior" or "round-trip what two independent tests already cover," do NOT suggest it. Prefer removing redundant tests over adding new ones.

5. **No bikeshedding.** Description wording, schema `description` strings, table row ordering, comment phrasing, variable name aesthetic — skip. These are author preference; the reviewer's job is to catch behavior/correctness/clarity issues, not impose taste.

6. **Be specific about severity.** Use only:
   - `block` — must fix before merge (bug, missing test for new behavior, broken docs/code agreement).
   - `nit` — narrow definition above.
   - Everything else does not appear in the report.

   No `recommend`, no `suggestion`, no `consider` — those are the wrappers manufactured nits hide behind.

   Two markers are **not** severities and are exempt from this vocabulary, because each states a fact about the check rather than a judgement about the code: `note:` (used by 1.0 for branch-name violations and by 1.1 for the reviewer reminder) and `未驗:` (used by 2.1 when a suite could not be run). Both are required where their own section calls for them — a gate that cannot be executed has to say so, and forcing it into `block` / `nit` is what makes an agent write `pass` instead.

   `fail:` is the third word this report actually uses — Phase 1 records metadata checks as `pass` or `fail: <reason>`, and the Phase 4 template carries `fail:` on the Assignee/Labels, Title, and Description lines. It is **not** exempt: a missing label or a non-conforming title is a judgement about the PR, so **`fail:` counts toward the ❌ count and suppresses the `/x-pr-review` recommendation exactly as `block` does.** The two words differ only in which phase writes them; treat them identically at the gate.

   These are **gate verdicts** for this pre-flight checklist (a local report shown to the user, never posted as a PR comment) — not the label vocabulary used for posted review comments. Keep `block` / `nit` here; don't migrate this gate to a review-comment format.

7. **If the PR is clean, say so plainly.** Do not append observations or "things to consider in future PRs" — those belong in a separate conversation, not in a pre-flight report.

8. **Read source aggressively, ask sparingly.** Default to reading files, grepping the repo, inspecting the diff, and checking surrounding context to form a judgment. Only ask the user when:
   - The answer is genuinely outside the codebase (e.g., "is this PR meant to be a draft?", "is this a breaking change you intend to merge as-is?").
   - You have two equally good options and the choice is a value preference, not a fact.

   Do NOT ask the user about anything you can determine by reading. Do NOT ask "which label should I pick" or "how should I word the title" when the diff content makes the answer obvious. Decide, act, and report what you did — let the user correct if they disagree.

---

## Reading Source Context (Applies to Every Phase)

Before producing a finding or making a recommendation, read the relevant files. The PR's `files` list from `gh pr view` is a starting point, not a complete picture.

Things to read by default:

- **The actual changed files** — open them at the touched line ranges, not just the diff snippet. The diff hides surrounding context (function signatures, struct fields, callsites) that often changes a finding's validity.
- **Files that import or depend on changed symbols** — `grep` for the symbol name across the repo. A type signature change with downstream callers is different from one without.
- **Existing tests for the touched area** — to judge coverage gaps, you need to know what's already tested, not just what's in the diff.
- **Sibling files in the same package** — to judge convention consistency (naming, doc-comment style, error-handling pattern).
- **Schema / proto / spec definitions** — if the diff changes a Go type that mirrors a schema, verify both sides moved in sync. Read both files.
- **CLAUDE.md (root and nested)** — for project-specific rules that override defaults.
- **Existing PR conventions** — `gh pr list --state all --limit 10 --json labels` to see what labels other PRs typically use, when an inference from diff alone is ambiguous. Reviewers are not inferred from history (1.1).

When you find a possible issue, before reporting it: **read the surrounding 30 lines** and **grep for the symbol** to confirm the issue is real and not a misread of the diff. Apply this false-positive check proactively, before any finding is raised.

---

## Phase 0: Gather PR Context

Resolve the PR number from the user's prompt. If the user did NOT provide one, **auto-detect** it — do NOT ask. In priority order:

1. Current branch → open PR:
   ```bash
   gh pr view --json number,title,body,headRefName,baseRefName,assignees,reviewRequests,reviews,labels,files,additions,deletions
   ```
   `gh pr view` with no arg resolves to the PR for the current branch. If it succeeds, use that PR number.
2. If step 1 fails (no PR for current branch), list this user's open PRs and pick the most recently updated:
   ```bash
   gh pr list --author "@me" --state open --json number,headRefName,updatedAt --limit 5
   ```
   If exactly one result, use it. If multiple, pick the one whose `headRefName` matches the current branch; otherwise the most recently updated.
3. Only if both fail with zero candidates → ask the user once for a PR number.

Once the PR number is resolved, fetch full metadata:

```bash
gh pr view <num> --json number,title,body,headRefName,baseRefName,assignees,reviewRequests,reviews,labels,files,additions,deletions
```

Announce the resolved PR number at the top of the report.

### Code source: prefer local over PR remote

The diff to review is **not** automatically `gh pr diff <num>`. Determine the code source as follows:

1. Extract `headRefName` from the PR metadata (call it `<head>`).
2. Check whether the local repo has that branch checked out or available:
   ```bash
   git rev-parse --abbrev-ref HEAD                       # current branch
   git rev-parse --verify --quiet <head>                 # local ref exists?
   git rev-parse --verify --quiet origin/<head>          # remote ref (after fetch)
   ```
3. Pick the diff base in this priority order, and **announce the choice at the top of the report**:

   | Condition | Diff command | Announce as |
   |-----------|--------------|-------------|
   | Current branch == `<head>` and there are commits ahead of `origin/<head>` (i.e. unpushed work) | `git diff <baseRefName>...HEAD` | `review base = local HEAD (N commits ahead of origin)` |
   | Local branch `<head>` exists (not currently checked out) | `git diff <baseRefName>...<head>` | `review base = local branch <head>` |
   | No local branch, but `origin/<head>` exists after a fetch | `git diff <baseRefName>...origin/<head>` | `review base = PR remote (fetched refs)` |
   | No local branch and no fetched `origin/<head>` | `gh pr diff <num>` | `review base = PR remote` |

   Rationale: the user's typical workflow is `amend locally → pre-flight → push`. Reviewing the PR remote after a local amend reviews stale code and creates false findings about issues the user has already fixed. Local is the source of truth when it exists; PR remote is the fallback for PRs whose work is not in the current workspace.

   The fetched-refs row exists because `origin/<head>` is routinely present without any local branch — after a plain `git fetch`, and always after `x-pr-review`'s clone step. Two real refs beat `gh pr diff`: they give a three-dot diff (so a base branch that moved ahead does not pollute the result — measured on a real PR, an unrelated two files appeared in the naive diff), they let you read either side in full with `git show`, and they cost no API calls. Reach for `gh pr diff` only when no ref pair exists.

4. If `git status` shows uncommitted changes on the head branch, include them in the diff base (`git diff <baseRefName>`). Mention in the announcement: `+ M uncommitted changes`.

Also detect repo conventions:

- Read root `CLAUDE.md` (if any) for project-specific rules.
- Identify whether the repo uses `README.md` + `README.zh-TW.md` pair.
- Identify whether the repo has a `docs/` directory and an index file (`docs/README.md`).

Do not start any phase until Phase 0 data is in hand.

---

## Phase 1: PR Metadata

Check each item independently. For each, record `pass` or `fail: <reason>` — except the two items whose own section says otherwise: 1.0 Branch Name and 1.1's Reviewer line record `note:` instead, because neither can be acted on here (rule 6 above). Do not invent additional metadata checks.

### 1.0 Branch Name

Validate `headRefName` on two rules, which have different owners. The prefix rule is `x-git-ops`'s (its `references/workflow.md`, 「Branch Naming & Base」); the slug rule is this gate's own — `x-git-ops` states nothing about slugs, so do not cite it for that half.

- Prefix MUST be one of `feature/`, `release/`, `hotfix/`. Anything else (`feat/`, `fix/`, `refactor/`, `bugfix/`, …) → `note: branch prefix violates git-flow`.
- Slug (the segment after the prefix) MUST describe intent in words. It MUST NOT begin with a `<word>-<number>-` ID-first token referencing an external tracker (`bug-364-`, `issue-123-`, `arx-2456-`, `jira-xxx-`, etc.). Tracker IDs belong in the PR body (`Closes #N`), not in the branch name. → `note: branch slug starts with tracker ID`.
- `release/*` slug is exempt from the ID-first rule (version strings like `release/v1.2.0` are expected).

Both are `note:`, not `block:` — do NOT instruct the user to rename. The reason is not that a pushed branch is immutable: force-pushing a feature branch is routine here (〈Applying Metadata Fixes〉rule 5 permits it, and any conflict resolution or squash after the PR opens ends in one). A rename is a different operation: it replaces the **head ref itself**, and the local way to do that — `git branch -m`, push the new name, delete the old — closes the PR along with its old head branch, so it is a re-open rather than an edit. Refs are also outside what this gate edits at all: 〈Applying Metadata Fixes〉covers PR title, body, labels, and the commit message, and nothing else. So this finding can only be recorded, which is what `note:` is for — it prints in the report, does not count toward ❌, and does not suppress the `/x-pr-review` line. Grading it `block` instead wedges the caller — an orchestrator that requires a clean re-run of this gate before advancing would loop forever on a finding this section itself says not to fix.

### 1.1 Reviewer / Assignee / Labels

- **Reviewer**: informational only — never a gate. Read both `reviewRequests` and `reviews`: requested **or** reviewed → `pass`. If neither, surface a one-line `note: reviewer 未指定` reminder — this does NOT count as a `fail` and does NOT flip the verdict. Reviewer selection is a GitHub-UI step by convention; do not infer or auto-assign one unless the user explicitly asks.
- **Assignee**: at least one assignee set. If none → `fail`.
- **Labels**: at least one label set. If none → `fail`.

Assignee and Labels are presence checks. When one fails, infer a sensible candidate from context rather than asking — the user will correct you if wrong.

**Inferring a label** (when `fail` and the user asks you to fix it):
1. Run `gh label list` to see the available label set in this repo.
2. Map the diff to a label using these signals — pick the **first** matching rule:
   - Diff modifies `*_test.go` only, or fixture files only → no label change needed for "test"; fall through to behavior class.
   - Diff is docs-only (`*.md`, `docs/**`, `README*`) → `documentation`.
   - PR title starts with `fix(...)` or `fix!:` → `bug`.
   - PR title starts with `feat(...)`, `refactor(...)`, or has `!` (breaking) → `enhancement` (closest available match unless repo has `refactor` / `breaking-change` labels).
   - PR title starts with `chore(...)`, `ci(...)`, `build(...)`, `style(...)` → no clear label; ask the user only if there are no plausible labels in the repo.
3. If multiple labels apply (e.g., a feature that also adds docs), pick the **most specific to the primary intent** — usually inferred from the title type, not the file mix.

**Reviewer**: do NOT infer one from history. Assign a reviewer via `gh pr edit --add-reviewer` only when the user has explicitly named one (pre-specified in the prompt or in reply to the `note: reviewer 未指定` reminder). Otherwise leave it — the reminder is the whole action.

**Inferring an assignee**: the PR author is the safe default. Do not assign to anyone else without explicit user instruction.

Decide, apply via `gh pr edit`, and report what you did. Do not pre-ask the user "which label?" when the diff content makes the answer obvious.

### 1.2 PR Title

- Must follow Conventional Commits: `type(scope)!?: subject`. Invoke the `x-git-ops` skill and load its `references/commit.md` for the allowed type list.
- Length **≤ 72 ASCII characters** (count actual chars, not visual width).
- If `!` is present, the description must mention the breaking change (cross-check in 1.3).

### 1.3 PR Description

- **Language**: body may be Taiwan Traditional Chinese (台灣繁體中文), English, or a mix of both.
  - **Taiwan terminology when Chinese is used** — use Taiwan conventions, not China mainland equivalents. Examples (Taiwan / mainland):
    - 程式 / 程序, 伺服器 / 服務器, 資料庫 / 數據庫, 正規表達式 / 正則表達式, 函式宣告 / 函數簽名.
    - Additional rejected mainland terms include but are not limited to: 数据库, 服务器, 函数, 打印, 缺省, 队列, 内存, 网络, 文件夹, 视频, 软件, 硬件, 默认. Do NOT add 配置 to this list — it is acceptable Taiwan tech vocabulary (動態配置, 網路配置, etc.); only flag the compound 配置文件 if seen, since Taiwan uses 設定檔.
  - **English technical terms are not just allowed — they are often preferred.** Keep terms like `goroutine`, `Race Condition`, `mutex`, `channel`, `defer` in English. The same applies to other engineering vocabulary that reads more precisely in English: `controller`, `reconcile`, `reviewer`, `assignee`, `label`, `webhook`, `CEL rule`, `CRD`, `RBAC`, `admission`, `schema`, `endpoint`, `payload`, `retry`, `timeout`, `request` / `response`, plus all code identifiers, API / RPC names, file paths, and product names.
    - Do NOT flag a description for using English in these places.
    - Do NOT suggest translating them to Chinese (e.g., do not propose 「控制器」 over `controller`, 「協調」 over `reconcile`, 「審查者」 over `reviewer`).
  - A fully English description is acceptable — do NOT flag it.
  - Reject only: Simplified Chinese characters (簡體中文) and China mainland terminology, per the list above.
  - **Judge semantically** by reading the body. Flag any Simplified character or mainland term as `block: PR description 使用中國大陸用語 "<term>" (line N)`, citing every match. No grep ritual — if a term is ambiguous, look it up; don't run a fixed regex list.
- **Consistency with diff**: skim the diff and confirm the description's bullet points map to actual changes. Flag if:
  - The description claims a change that does not appear in the diff.
  - The diff contains a non-trivial change (new file, public API change, breaking change) not mentioned in the description.
- If title has `!`, body must call out the breaking change explicitly.

Do NOT comment on:
- Description wording, structure, or section ordering.
- Whether the description is "thorough enough" beyond the consistency check above.

---

## Phase 2: Test Review

Identify test files touched in the diff (`*_test.go`, `*.test.ts`, `__tests__/*`, etc.). For each, ask exactly three questions — and only raise findings backed by a concrete answer.

### 2.1 Coverage Gaps

Question: *Does the diff introduce new branches, error paths, or public behavior with no corresponding test?*

- **Build + run the tests before declaring Coverage `pass`.** Reading the diff only confirms "a test file exists" — it does not confirm the tests pass or that the code builds. Run, at minimum:
  - The project's build (`go build ./...`, `npm run build`, etc.)
  - The tests for every package the diff touches, with race detection where applicable (e.g. `go test -tags=sqlite -race ./<changed-pkgs>/...`)

  Cite the actual commands and outcomes on the Coverage line. If build or any test fails → `block` (do not list missing-coverage findings until the suite is green; failures dominate). For PRs that span many packages, run the touched packages, not the whole repo.

  **Partial execution has its own wording — `pass` is not available for a suite you did not run.** Two different things block this gate, and they need separate answers.

**(a) Missing external services** (Postgres, Vault, a cluster). That never makes the whole gate unrunnable: `go build ./...` needs none of them, and the pure-logic packages usually run standalone.

**(b) The PR head is not checked out** — Phase 0's third row (`review base = PR remote`) is exactly this state, and a freshly cloned repo (which lands on the default branch) is another. **Name the tree you built before citing any command.** Running `go build ./...` in a repo sitting on `develop` compiles the wrong code, comes back green, and gets cited as verification of a diff that was never compiled. Run against the head without switching branches or touching the working tree:

```bash
~/.claude/skills/arx-pr-pre-flight/scripts/pr-head-tree.sh --repo <repo> --pr <num> \
  -- sh -c 'go build ./... && go test ./<changed-pkgs>/...'
```

Everything after `--` is the command, and **it runs with cwd at the tool root** — so relative paths in it are relative to the extracted tree, not to your shell. The script removes the tree on exit and prints `REF:` / `TREE:` / `SUBMODULE:` (one per submodule) / `EXIT:` / `VERDICT:`. **Cite the `REF:` line** — that is the evidence for which tree you built, and it is the thing a `pass` on this line is claiming.

`--subpath P` moves the tool root to `<tree>/P`. Omit it for Go (`go build ./...` needs `go.mod` at the top of the extracted tree); pass the chart's own directory when the tool is `helm unittest`. The tool decides — this is not a repo-root rule with a chart exception.

If the script cannot produce a tree at the head ref, the gate is `未驗` for everything, not `pass`.

**A `VERDICT:` carrying `TREE INCOMPLETE` is also `未驗`, whichever way the command exited.** `git archive` writes a submodule as an empty directory, and the script can only fill it from your local clone — a submodule you never initialised stays empty, and it says so on both the `SUBMODULE:` line and the verdict. Both exits then mean the same thing, and neither is about the PR:

- `ok` + `TREE INCOMPLETE` — the command passed **by never reading through the empty directory**. Writing `pass` here is the false-clean this marker exists to stop.
- `failed` + `TREE INCOMPLETE` — the command died *on* that gap, so the "build or any test fails → `block`" rule below does not apply. Blocking a PR for a hole in the reviewer's own checkout is the worse of the two mistakes.

Either way write `未驗: <what the tree was missing>` and read CI at the head SHA for that suite, exactly as for a tree you could not produce at all.

So split the outcome, and write all three parts on the Coverage line: **what you ran** (command + outcome), **what you skipped and which dependency blocked it**, and **CI's verdict at the head SHA** for the skipped part:

  ```bash
  gh pr checks <num> --json name,state,link          # or: gh api repos/<o>/<r>/commits/<sha>/check-runs
  ```

  CI's three states map straight through, and **none of them makes you wait**:

  Only the checks that **cover the suite you skipped** are read here — identify them by name. Reds elsewhere on the PR are not this gate's business, and per this workspace's convention a red `security` / vulnerability scan is expected and ignorable, so keying off "any failure" would turn routine scanner noise into a `block` on a PR nothing showed to be broken. Read the JSON `state` field, never `gh pr checks`'s exit code — it exits non-zero for pending as well as failing.

  | the check covering the skipped suite | Coverage line says |
  |---|---|
  | green | `pass (CI <check> @ <sha>)` — the suite did run, on CI rather than here, so `pass` is honest and must name where |
  | failing | `block` — a real failure, same as a local one |
  | still running, or no such check exists | `未驗:<what> — CI <check> in_progress` (or `no CI covers this`) and continue |

  Do not poll, wait for, or re-run CI to close this gate — its state is a fact you record, not a milestone you block on. The rule this replaces offered only `pass` or `block`, and Rule 6 lets nothing else into the report, so partial satisfiability forced a choice between two false statements: `pass` on a suite that never ran, or `block` on code nothing showed to be broken.
- Raise `block` if a new branch / error path / public API surface has zero coverage.
- **"New behavior" includes non-Go contract surfaces**: CRD CEL rules (`x-kubernetes-validations`), admission webhook predicates, OpenAPI validation, generated schema constraints, RBAC policies. If the PR adds one and there is no automated test (envtest for CEL, integration test for webhooks, policy test for RBAC), that is a coverage gap — **not a nit**.
- **Load-bearing invariant test**: if the PR's design narrative argues "we no longer need X because Y enforces it" (e.g., "controller skips owner-name check because CEL enforces same-name"), the test that pins Y is what makes the design sound. Missing that test → `block`. Do NOT downgrade to `nit` because adjacent Go-level tests exist — they cover a different layer.
- **Sibling-field parity check**: when the diff adds a new field to a struct / schema / message that has existing sibling fields, the new field MUST receive the same downstream validation as its siblings. Before declaring Coverage `pass`:
  1. Identify the parent type (e.g., `StorageBinding`, `NetworkPort`, an OpenAPI object).
  2. Grep for one or two existing sibling field names (e.g., `StorageClass`, `AccessMode`) across the repo to map every function / validator / checker that touches them.
  3. Grep the new field name (e.g., `SubPath`) and confirm it appears in the same set of callsites. If a sibling is validated at layer X (schema lint, chartcheck, controller webhook, audit) but the new field is not → `block`.
  Skipping this check is the failure mode that lets cross-layer invariant gaps (e.g., spec-side chartcheck verifies storageClass/accessMode keypaths but not the new subPath keypath, even though the downstream proto no longer carries keypaths) slip through pre-flight. The PR's own diff will not surface the gap; only the sibling-field grep will.
- Do NOT raise "could add more cases" speculation. Either an uncovered branch / contract exists, or it doesn't.

### 2.2 Table-Driven Simplification

Question: *Are there 2+ `t.Run(...)` (or framework equivalent) blocks with identical setup and assertion logic differing only in inputs/expected outputs?*

- If yes → `nit`: suggest consolidating into a table. Cite the specific blocks.
- If subtests have different mocks / different assertion types / different error shapes → keep separate. Do NOT force-table them.

Invoke the `x-coding-standards` skill and load its `references/go-testing.md` before raising this for Go code, to confirm the table refactor is actually appropriate.

### 2.3 Over-Testing / Redundancy

Question: *Does any test pin behavior that belongs to a library, or duplicate a contract already covered by another test in the same PR?*

Common smells (raise as `block` if removing the test would not lose any protected invariant):

- **Library behavior tests**: tests that pin `yaml.Marshal`, `json.Marshal`, ORM default behavior, framework routing defaults, etc. These test the dependency, not your code.
- **Round-trip tests** when parse-direction and marshal-direction are both already tested independently.
- **Strict full-output equality** (`assert.Equal` on a full serialized blob) when the goal is "key X is present/absent" — this couples the test to library output format and breaks on library upgrades that didn't break your code.
- **Boundary tests at multiple layers** for the same constraint (e.g., schema validator already tests `0` rejection — the Go type parse test doesn't need to re-test it).

For every over-testing finding, your one-sentence justification (per Rule #3) must answer: *what invariant would we lose by deleting this test?* If the answer is "none," the test should go.

---

## Phase 3: Doc Review

### 3.1 README sync

If the repo has both `README.md` and `README.zh-TW.md`:

- If the PR modifies either, the other must be updated in the same PR. → `block` if not.
- Compare structure (headings, sections): they must match. → `block` if drift introduced.

Do NOT comment on translation phrasing quality.

### 3.2 docs/* updates

**Important:** `docs/` contains both auto-generated and hand-written files. Pre-flight must check both — not just confirm the generated ones moved.

**Auto-generated (regen check only)** — verify they were regenerated when the source changed, but do NOT review their content:
- `docs/grpc/API-Reference.{md,json}` — from `buf generate`
- `docs/swagger/**`, `docs/openapi/**` — from openapi-gen
- `docs/proto/**` — from protoc-gen-doc (whole directory is generator output)
- Anything with a `DO NOT EDIT` header or listed as generated in root `CLAUDE.md`

Check: if the diff touches proto / OpenAPI source but the matching generated doc is unchanged → `block: missing regen`. If the user manually edits a generated file → `block: generated file edited by hand`.

**Hand-written (content sync check)** — these MUST be kept in sync with behavior changes:
- `docs/*.md` at top level (e.g., `Architecture.md`, `Services.md`, `Configuration.md`, `Error-Codes.md`, `List-API-Guide.md`, `Interceptors.md`, etc.)
- `docs/subsystems/**`, `docs/flows/**`, `docs/configuration/**`
- `README.md`, `README.zh-TW.md`, nested `README.md` in subpackages

Walk the diff and ask, for each non-trivial code change:

1. **Behavior / public API change** → does any hand-written doc describe this behavior or API? If yes, the doc must be updated in the same PR. → `block` if not.
   - Examples: new RPC method, changed error code mapping, new config key, changed default value, new lifecycle stage, new interceptor, new audit event semantics, new validation rule.
2. **Convention / pattern change** → does CLAUDE.md or a `docs/*.md` style guide reference the old pattern? → `block` if doc still describes the superseded form.
3. **New doc file** → is it linked from `docs/README.md` (or the docs index)? → `block` if orphaned.
4. **Diagram / cross-reference change** → if the diff renames a symbol, file, or section that another doc links to, the link must still resolve. → `block` if broken.

Grep aggressively before concluding "no doc affected":
- `grep -r "<symbol name>" docs/` for any new/changed public API symbol.
- `grep -r "<config key>" docs/` for any new/renamed config key.
- `grep -r "<old name>" docs/ README.md README.zh-TW.md` when renaming.

Do NOT comment on:
- Doc style, heading depth choice, or table column order.
- Whether the doc "could be clearer" without a specific broken claim.
- Generated file content (only its presence / staleness).

### 3.3 Mainland terminology check on changed Chinese docs

Same rule as 1.3, applied to hand-written Chinese `.md` files the diff touches. **Read the added lines semantically** — do not run a fixed regex list.

- Scope: only the `+` lines this PR adds (pre-existing wording is not the author's responsibility), and only hand-written files. Exclude generated docs — `docs/swagger/**`, `docs/openapi/**`, `docs/proto/**` (whole directories of generator output) and **`docs/grpc/API-Reference.{md,json}` only, not `docs/grpc/**`** — and `README.md` (English-only by convention). `README.zh-TW.md` is included.
- Flag Simplified characters and mainland terminology as `block: 新增行使用中國大陸用語 "<term>"` and cite file:line for each match.
- If ambiguous, look up the term; don't pad the finding list with maybes.

---

## Phase 4: Gate

Produce a final report in this exact shape (in 台灣繁體中文):

```markdown
## Pre-Flight 報告：PR #<num>

> Review base: <one of: local HEAD (N commits ahead of origin) | local branch <head> | PR remote> [+ M uncommitted changes]

### PR Metadata
- Branch name: <pass | note: … (non-gating)>
- Assignee/Labels: <pass | fail: …>
- Reviewer: <pass | note: reviewer 未指定 (non-gating)>
- Title: <pass | fail: …>
- Description: <pass | fail: …>

### Tests
- Coverage: <pass | pass (CI <check> @ <sha>): … | 未驗: … (a run whose VERDICT carried TREE INCOMPLETE lands here) | block: …>
- Table-driven: <pass | nit: …>
- Over-testing: <pass | block: …>

### Docs
- README sync: <pass | block: … | n/a>
- docs/* updates: <pass | block: … | n/a>

### 判定
<one of:>
- ✅ 全部通過。建議執行 `/x-pr-review <num>` 進行深度 review。
- ✅ 其餘通過，Coverage 未驗（<what>）。建議執行 `/x-pr-review <num>` 進行深度 review。
- ✅ 其餘通過，Branch name <what>（下次注意）。建議執行 `/x-pr-review <num>` 進行深度 review。
  <both carried when both apply: `✅ 其餘通過，Branch name <what>（下次注意）、Coverage 未驗（<what>）。…`>
- ❌ 有 N 項需處理，列在上方；處理完再跑 `/x-pr-review`。
```

Rules for the report:

- If a section has no findings, write `pass` on that line. **Do not** add observations, alternative phrasings, or "future considerations."
- `nit` findings do NOT block the recommendation to run `/x-pr-review`; they are informational.
- A `note` (1.0 branch name, 1.1 reviewer 未指定) is informational only — it does NOT count toward the ❌ item count and does NOT suppress the `/x-pr-review` recommendation. A report whose only non-pass lines are notes is still ✅. The two differ in whether they reach the 判定 line: 1.1's reviewer note does not, because an unassigned reviewer is a UI step someone has yet to do rather than something wrong with the PR. **1.0's branch-name note must be carried** — write `✅ 其餘通過，Branch name <what>（下次注意）`. It is a real violation that this PR is structurally unable to fix, so a bare ✅ over it is exactly how the reminder gets lost, and being unfixable here is what makes carrying it the only thing this gate can do about it.
- A `未驗` (2.1, a suite that could not be run) does NOT count toward the ❌ item count and does NOT suppress the `/x-pr-review` recommendation — it reports that a gate could not execute, which is not a finding against the code. But it must be **carried into the 判定 line**, not dropped: write `✅ 其餘通過，Coverage 未驗（<what>）` so the reader sees the gate was skipped rather than passed. A silent ✅ over a `未驗` line is what the marker exists to prevent.
- `block` findings DO suppress the `/x-pr-review` recommendation.
- Do NOT auto-invoke `/x-pr-review`. The skill's job ends at the recommendation; the user runs it themselves.

---

## Applying Metadata Fixes (Opt-In, Diff-First)

The skill MAY apply fixes to PR title, PR body, labels, or the commit message **only** when the user explicitly opts in after seeing the report — phrases like "fix all", "fix the blocks", "直接改", "幫我改 PR title". Producing the report alone is never a license to edit.

When applying any text edit (commit message, PR title, PR body, label change), follow this protocol — no exceptions:

1. **Show the before/after diff first** in chat as a fenced ```diff code block (so it renders with +/- color highlighting), one diff per artifact (commit title, commit body, PR title, PR body section). Use `-` for removed lines and `+` for added lines, quoting the exact text — do not paraphrase, do not summarize as prose, do not show only the "after" version.
2. **Wait for explicit confirmation** ("ok", "go", "改吧") before running `gh pr edit`, `git commit --amend`, or `git push`.
3. Batch all diffs into a single confirmation round when possible — do not drip-feed edits across multiple turns.
4. If the user pushed back on an earlier edit in the same session, re-show the diff even for follow-up edits the user requested; do not assume the diff-first rule lapses after one approval.
5. Force push (`--force-with-lease`) is allowed for feature branches the user owns once the diff is approved; never force-push to `develop` / `main` / `release/*`.

Out of scope even with opt-in: code-level fixes to the diff under review.

---

## What This Skill Does NOT Do

- Does not run the deep code review itself (that's `x-pr-review`).
- Does not fix code-level findings raised in the report.
- Does not check CI status as a gate of its own (CI is a separate gate) — with one carve-out
  that 2.1 requires: when a test suite could not be run locally, read CI's result **at the
  head SHA for that suite** and cite it on the Coverage line. That is citing a fact to close
  a gate this skill owns, not adopting CI as a gate; every other check stays out of scope,
  and no check outside the skipped suite may flip a verdict here.

Metadata-level fixes (PR title / body / labels / commit message) are permitted only when the user explicitly asks to apply them — see "Applying Metadata Fixes" above. The default after producing the report is to stop.

---

## Anti-Patterns to Avoid (Calibration Examples)

These are real failure modes the skill must resist. If a finding sounds like any of these, drop it.

| Tempting finding | Why it's wrong |
|------------------|----------------|
| "Description could mention X is also affected" | Author preference; not a consistency break |
| "Table column order would read better as A→B→C" | Bikeshedding |
| "Schema `description` could be clearer" | Wording preference, no behavioral impact |
| "This test uses `assert.Contains`; `assert.Equal` would be stricter" | Adds library coupling without protecting a new invariant |
| "Consider adding a round-trip test" | Redundant if parse and marshal are tested independently |
| "Could split this commit message into more bullets" | Style preference; out of scope |
| "Variable name `cfg` could be `config`" | Style preference unless project convention says otherwise |

If a finding does not clearly fit `block` or the narrow `nit` definition — drop it.

### Severity-Downgrade Anti-Patterns (Do Not Do This)

The mirror failure of manufactured nits: real `block` findings dressed as `nit` to feel "calibrated / restrained." If you catch yourself doing any of these, **promote to `block`**:

| Tempting downgrade | Why it's actually `block` |
|---------------------|----------------------------|
| "CEL rule / webhook / RBAC has no automated test, but Go-level tests pass — `nit`" | The schema/admission/policy layer IS the new behavior. Adjacent tests cover a different layer. |
| "The design relies on X enforcing Y, X has no test — `nit`, the controller code is tested" | If the PR's reasoning depends on X being correct, the absence of X's test breaks the reasoning. |
| "Missing test for new behavior, but the test plan has a manual `kubectl` checkbox — `nit`" | Manual verification is one-shot; it does not protect against regen / refactor regressions. |
| "Could be a `block` but feels harsh, calling it `nit` with strong wording instead" | If the body of the finding argues for blocking, the label must match. Wording-strength is not a substitute for severity. |

The skill warns against manufactured nits AND against downgrading real blocks. Both are calibration failures. The test for severity is the body of your justification: if removing or skipping the suggestion would leave a load-bearing invariant unverified, it is `block`.
