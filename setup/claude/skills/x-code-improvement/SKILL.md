---
name: x-code-improvement
description: Reviews branch changes with two parallel agents (reuse + altitude; quality + efficiency), applying project coding standards, then fixes issues found.
model: haiku
---

# Code Improvement

Reviews code changes within a specified commit range. Reads project and user coding standards dynamically. Launches two review agents in parallel (reuse + altitude; quality + efficiency), validates findings, then fixes confirmed issues, reporting what it skipped and why.

## Parameters

| Parameter | Example | Description |
|-----------|---------|-------------|
| (none) | `/x-code-improvement` | Default: base branch...HEAD |
| `A..B` | `/x-code-improvement abc123..HEAD` | Custom commit range; B must resolve to HEAD (the script stops otherwise) |

## Step 1: Detect modified files

**Determine the diff range:**
- If the user provided a commit range (e.g., `A..B`), put `RANGE="A...B"` (three-dot form) as the first line of the script below; the script keeps it and only auto-detects when `RANGE` is unset.
- Otherwise, auto-detect the base branch.

**Critical**: Pass the entire script below as a single Bash tool call — shell variables do not persist across separate calls. Run it inside the repo: when cwd is not the repo (a worktree folder holding several), make `cd <repo path> &&` its first line.

```bash
CURRENT_BRANCH=$(git branch --show-current)
echo "Current branch: $CURRENT_BRANCH"

# Base: origin/ first — the main clone's local develop is often unpulled, and a stale base
# pulls teammates' merged commits into the range
BASE=""; for b in origin/develop develop origin/main main; do git rev-parse --verify -q "${b}^{commit}" >/dev/null && { BASE="$b"; break; }; done
[ -n "$BASE" ] || BASE=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
RANGE="${RANGE:-$BASE...HEAD}"
# A user-given range must end at HEAD: the agents read and the fixer edits the working tree.
L="${RANGE%%...*}"; R="${RANGE##*...}"
if [ "$L" = "$RANGE" ] || [ -z "$L" ] || [ -z "$R" ]; then echo "ERROR: range must be A...B with both sides set: $RANGE"; exit 1; fi
if ! git rev-parse --verify -q "${L}^{commit}" >/dev/null; then echo "ERROR: cannot resolve $L"; exit 1; fi
if [ "$(git rev-parse "$R" 2>/dev/null)" != "$(git rev-parse HEAD)" ]; then echo "ERROR: right side $R is not HEAD - check out that branch first"; exit 1; fi
echo "PROJECT=$(git rev-parse --show-toplevel)"
echo "Base: $BASE"
echo "Diff range: $RANGE"
# Agents diff from here to the WORKING TREE, so uncommitted edits are reviewed too
echo "DIFF_BASE=$(git merge-base "$L" HEAD)"

echo ""
echo "=== Committed changes ==="
git diff --name-only $RANGE

echo ""
echo "=== Uncommitted changes ==="
git diff --name-only HEAD
```

Keep three printed values; every subagent prompt below carries them as literal strings: `PROJECT=` in place of `<PROJECT>`, `DIFF_BASE=` in place of `<DIFF_BASE>`, `Diff range:` in place of `<RANGE>`. Subagents run in their own shell and cwd: no variable from this script exists there, and cwd is usually the worktree folder above the repo, so a bare `git` call fails or runs in another repo. Every git command in a subagent prompt is `git -C <PROJECT> ...`, and every file path is given under `<PROJECT>`. The diffs use `<DIFF_BASE>` with no right side, which compares against the working tree — a committed-only `<RANGE>` diff shows nothing for an uncommitted change, and the run would report "No issues to fix." having reviewed nothing.

If the script printed `ERROR:`, report it and stop.

**Write the intent summary now, before Step 2.5 picks a path** — both paths' fixer needs it. Two or three sentences on what problem this change solves, from what this session already knows (the user's request, the issue, the PR description). If the session has none, run `git -C <PROJECT> log --right-only <RANGE>` and write it from those commit messages (`--right-only` because a three-dot log also lists the base side's commits); when they are too thin, say so in the summary.

Merge the committed and uncommitted lists (deduplicate) into the candidate file list. It is filtered at the start of Step 2, once the exclusion list is loaded.

## Step 2: Read coding standards

**First, filter.** Invoke the `x-coding-standards` skill and drop every candidate file its "Generated & Lock File Exclusions" section excludes (both tests: the generated-Go content marker and the filename regex). The result is the target file list. If no files remain, inform the user and stop.

Then read the following to understand project conventions (skip files that do not exist):
- Project-level: `CLAUDE.md`, `DESIGN.md`, `CONTRIBUTING.md`
- **Language & interface references**: From the `x-coding-standards` skill already loaded, load every reference whose condition the changed files hit — by language (Go `.go`, Helm chart `.yaml`) and by interface (HTTP handler, API request/response schema). A single `.go` handler hits both kinds.

Include a summary of the applicable standards in each agent's prompt so they can apply them.

## Step 2.5: Triage — lightweight or full review

Based on the diff from Step 1, decide the review path:

- **Lightweight** (main context review): Single file changed, single logical modification (e.g., adding a sort, fixing a condition, renaming), no new patterns or abstractions introduced. Read the diff and apply all review dimensions (reuse, altitude, quality, efficiency) directly in the main context, writing findings in Step 3's output format with the `[dimension]` tags — Step 4's fixer reads the tags to keep `[altitude]` report-only. Skip to Step 4 for fixes if needed.
- **Full** (2-agent parallel review): Multiple files changed, new patterns or abstractions introduced, or cross-module modifications. Proceed to Step 3.

## Step 3: Launch two review agents in parallel

Using the Agent tool, launch both agents **concurrently in a single message** with `model: sonnet`. Pass each agent the **file list**, the literal `<PROJECT>`, `<DIFF_BASE>` and `<RANGE>` values (from Step 1's output), and the **coding standards summary**. Agent 1 also gets the **intent summary** from Step 1. The altitude check judges whether the fix sits at the root cause, which cannot be judged without knowing the problem, and the agent sees none of this conversation. When the summary says the context is too thin, Agent 1 reports altitude only where the special case is evident without knowing the goal.

**Context strategies (critical — each agent collects context differently)**:
- **Agent 1 (Reuse + Altitude)**: Reads changed files fully + searches broader codebase with Grep. Needs full file context to find reuse opportunities, and to see the shared mechanism a special case is layered on — which is why altitude lives here and not in the diff-only Agent 2.
- **Agent 2 (Quality + Efficiency)**: Runs `git -C <PROJECT> diff -U10 <DIFF_BASE>` as its first step to get diff with 10 lines of surrounding context. **Does NOT read full files** — analyzes only the diff output. This is sufficient for quality/efficiency review and dramatically reduces token usage.

**Scope rules**:
- Agent 1 (Reuse + Altitude) may additionally search the broader codebase with Grep to find existing utilities.
- Agent 2 (Quality + Efficiency) should only analyze the diff output. **Critical: only flag issues in code that was added or modified in the diff. Do not flag pre-existing code, even if it appears in the context lines.**
- No agent should edit any files. Review only.

### Agent 1: Code Reuse + Altitude Review

For each change:
1. Search for existing utilities and helpers that could replace newly written code. Use Grep to find similar patterns elsewhere in the codebase -- common locations are utility directories, shared modules, and files adjacent to the changed ones.
2. Flag any new function that duplicates existing functionality. Suggest the existing function to use instead.
3. Flag any inline logic that could use an existing utility -- hand-rolled string manipulation, manual path handling, custom environment checks, ad-hoc type guards, and similar patterns are common candidates.
4. **Intra-change duplication**: Check whether new code in the diff duplicates other new code in the same diff. For example, a new function that manually re-implements parse/execute logic when another new function in the same change already encapsulates it. The fix is to reuse the existing new function, not to create a shared abstraction.
5. **Organizational convention**: When the diff adds a new type, interface, or file to an existing package, `ls` the sibling files in that package to check if the project has an established convention for where similar items live (e.g., interfaces in `interfaces.go`, errors in `errors.go`, types in `types.go`). Flag new items that break the convention.
6. **Stringly-typed code**: When the diff introduces raw string literals for values that look like identifiers (status codes, event names, config keys), Grep the codebase to check if constants, enums, or branded types already exist. Flag raw strings that should use existing definitions.
7. **Altitude**: Check that each change fixes the root cause at the right depth (against the intent summary) rather than patching a symptom. A special case layered on shared infrastructure — an `if name == "x"` branch inside a generic helper, a caller-side workaround for a callee's wrong value — is the sign. Name the more general change to the underlying mechanism. Flag only when you can name that mechanism's `file:line`; "this feels like a band-aid" without it is not a finding.
8. **Dead code left behind**: a helper, branch, or constant whose last caller the diff removed. Grep under `<PROJECT>` to confirm no caller remains before flagging; unused imports and locals are left to the compiler and linter. Tag it `[reuse]`.

**Scope constraint**: Searching the broader codebase is expected, but every finding must be about code **added or modified in the diff** that could reuse an existing utility, follow an existing convention, use existing constants, or move to the deeper mechanism item 7 names. Do not critique pre-existing functions themselves (e.g., "this existing helper duplicates stdlib" is out of scope). Item 8 is the one exception: the dead symbol predates the diff, but the diff is what removed its last caller.

### Agent 2: Code Quality + Efficiency Review

**First step**: Run `git -C <PROJECT> diff -U10 <DIFF_BASE> -- <file_list>` to collect the diff with 10 lines of context. All analysis below is based on this diff output only — do NOT use the Read tool to read full files.

Review the changes for both quality and efficiency issues in a single pass.

**Quality** — flag hacky patterns (all analysis based on diff output only):
1. **Redundant state**: state that duplicates existing state, cached values that could be derived, observers/effects that could be direct calls
2. **Parameter sprawl**: adding new parameters to a function instead of generalizing or restructuring existing ones
3. **Copy-paste with slight variation**: near-duplicate code blocks that should be unified with a shared abstraction
4. **Leaky abstractions**: exposing internal details that should be encapsulated, or breaking existing abstraction boundaries
5. **Complexity**: unnecessary nesting (use early return, guard clauses), redundant code, premature abstractions
6. **Naming**: unclear names that are not self-documenting
7. **Comments**: comments that describe obvious behavior instead of explaining why
8. **Anti-patterns** (flag when found):
   - Nested ternary expressions — prefer `if/else` or `switch`
   - Empty catch/except blocks that silently swallow errors — propagate the error to the caller; logging it and continuing is still swallowing it, unless continuing without that result is correct
   - Inverted error checks that silently discard errors — `if err == nil { use(result) }` skips the error path entirely; prefer `if err != nil { return err }` followed by the success path
   - Boolean parameters that control branching — prefer separate functions or an options struct/object
   - Deep callback nesting (callback hell) — prefer async/await, promises, or early return
   - Type assertions without error check (Go: `x := v.(T)` instead of `x, ok := v.(T)`)
   - Bare `return err` chains without context wrapping (Go: prefer `fmt.Errorf("...: %w", err)`)
   - Using deprecated or superseded stdlib APIs when a modern replacement exists in the same stdlib (e.g., `sort.Slice` → `slices.SortFunc`) — check user coding standards for known replacements

**Balance guardrail — clarity over brevity** (constrains both what you flag and how Step 4 fixes it): never trade readability for fewer lines. Do NOT flag or propose nested ternaries, dense one-liners, collapsing distinct concerns into one function, or removing a helpful abstraction. Explicit, readable code beats compact code; if a "simplification" makes code harder to read, debug, or extend, it is not an improvement.

**Efficiency** — flag performance issues:
1. **Unnecessary work**: redundant computations, repeated file reads, duplicate network/API calls, N+1 patterns
2. **Missed concurrency**: independent operations run sequentially when they could run in parallel
3. **Hot-path bloat**: new blocking work added to startup or per-request/per-render hot paths
4. **Unnecessary existence checks**: pre-checking file/resource existence before operating (TOCTOU anti-pattern) -- operate directly and handle the error
5. **Memory**: unbounded data structures, missing cleanup, event listener leaks
6. **Overly broad operations**: reading entire files when only a portion is needed, loading all items when filtering for one

**Output rules (all agents)**:
- Only output findings that require a code change. Do not describe improvements the PR already implements correctly.
- Each finding must state what should be changed and its **concrete cost** — what is duplicated (name the existing helper and its `file:line`), what work is wasted, or what becomes harder to maintain. A finding that cannot name its cost is a preference, not a finding.

Each agent must output findings in this format:

```
## [Reuse + Altitude|Quality + Efficiency] Findings

### file_path
- [reuse|altitude|quality|efficiency] Finding description and suggested fix — cost: <what is duplicated / wasted / harder to maintain>

### file_path
- [<dimension>] Finding description and suggested fix — cost: <...>
```

If no issues found, output "No issues found."

## Step 3.5: Filter false positives

Wait for both agents to complete. Launch an Agent tool subagent (`model: haiku`) to validate each finding, passing it the findings, the literal `<PROJECT>` and `<DIFF_BASE>`, and the same intent summary Agent 1 got — without it, altitude findings score low and vanish into `## Discarded`, which the user never sees:

1. Receive all findings from Agent 1 and Agent 2.
2. For each finding, run `git -C <PROJECT> diff -U10 <DIFF_BASE> -- <file>` to read the relevant diff context. When a finding names an existing helper, constant, or mechanism to use instead, Grep for that symbol under `<PROJECT>` and confirm it exists with the behavior claimed — the diff alone cannot show code outside it, and a reuse finding pointing at a helper that does not exist sends the fixer inventing one.
3. Merge findings that point at the same line or the same mechanism into one before rating — Agent 1's intra-change duplication and Agent 2's copy-paste item routinely flag the same block, and two fixes for one block conflict. Keep one tag: if any merged finding is `[altitude]`, the result is `[altitude]` (Step 4 leaves it report-only, since a local fix would preempt the deeper change); otherwise keep the first finding's tag. Fold the other findings' text and `cost:` into the description.
4. Rate each finding's confidence (0-100): Is this a real issue that requires a code change?
5. Output only findings with confidence ≥ 80, in the same format as the review agents (keep each `[dimension]` tag and `cost:` clause — the fixer decides report-only by the tag).
6. For discarded findings, output a one-line reason at the end under a `## Discarded` section.

This step does NOT find new issues — it only validates existing findings.

## Step 4: Fix issues

Wait for the filter to complete. Launch a single Agent tool subagent (subagent_type: general-purpose, model: sonnet) to aggregate the validated findings and fix each issue by editing the changed files. Pass the filtered findings, the coding standards summary, the file list (as paths under `<PROJECT>`), `<PROJECT>` and `<DIFF_BASE>`, and the intent summary to this subagent — it judges "intended behavior" and "outside the diff" below, and cannot without them.

**Findings tagged `[altitude]` are report-only.** Their fix moves logic into a shared mechanism outside the diff, which affects every other caller of it; list each under `## Skipped` with reason "needs a shared-mechanism change — report only" and do not edit for it.

**Dead-code findings on an exported symbol are report-only too.** A consumer in another repo cannot be grepped from here, and deleting the symbol changes a public API; list it under `## Skipped` with reason "exported — callers outside this repo unverified".

**Preserve functional behavior** -- only change how, never change what. Do not alter public APIs, return values, side effects, or error semantics.

**Clarity over brevity** -- honor the Balance guardrail from Agent 2: never make code more compact at the cost of readability; prefer explicit code over clever one-liners.

Skip a finding when its fix would change intended behavior, would require changes well outside the reviewed diff, or when you judge it a false positive. Do not skip silently: every skip goes in the `## Skipped` section below with its reason, because Step 5 shows your summary as-is and a dropped finding would otherwise vanish.

The subagent must output a summary of changes in this format:

```
## Changes

### file_path
- What was changed and why (which review dimension flagged it)

## Skipped

- file_path — finding — reason (changes behavior / outside the diff / false positive)
```

Omit `## Skipped` only when nothing was skipped.

If no changes were made, say so — and still include `## Skipped` when anything was skipped. Output only "No issues to fix." when there were no findings at all.

## Step 5: Present the result

Display the fix subagent's summary directly to the user, followed by the validator's `## Discarded` list (one line each) — otherwise a discarded finding, altitude ones especially, reaches nobody. If Step 2.5 took the lightweight path, prepend one line saying the review ran as a single pass in the main context, not the two-agent review — the fixer does not know which path ran, so only you can say it.

If any changes were made, remind the user: "Changes are not yet committed — commit them when ready."
