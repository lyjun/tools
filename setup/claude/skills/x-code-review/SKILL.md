---
name: x-code-review
description: Review branch changes for correctness and security defects only — a local base..HEAD, or an explicit A..B range such as a fetched PR's origin/base...origin/head (single-project only; cross-repo mode reviews each repo's own base..HEAD and takes no range) — logic bugs, nil deref, error-handling/rollback gaps, security issues, caller-impact breakage, missing safety guards, regressions against git history, and CLAUDE.md violations. Quality, style, reuse, and efficiency are out of scope. Use during development or before PR submission.
model: haiku
---

# Code Review

Reviews code changes using subagents to keep the main context clean. Auto-detects review mode based on directory structure.

## Parameters

| Parameter | Becomes | Description |
|-----------|---------|-------------|
| (none) | no flags | Auto-detect: incremental if PR has prior review, otherwise full |
| `full` | `--full` | Force full review (`BASE...HEAD`), skip incremental detection |
| `A..B` | `--range A..B` | Custom commit range (single-project only). Uses cwd as the repo |
| `<path> A..B` | `--repo <path> --range A..B` | Same, with the repo named explicitly — required when cwd is not itself a repo, since ref names cannot identify one (`origin/main` resolves in every repo) |

The middle column is how each form reaches Step 0's script; the left column is what the
user types. A form typed without its flag is the failure this column exists to prevent —
the script rejects an unknown bare argument rather than guessing which one it was.

Invoke by the full name. `/code-review` (alias `/review`) is a different, built-in review command — it takes
a PR number / branch / path plus an effort level rather than a commit range, also covers
reuse and simplification, and can post inline PR comments or edit the working tree.

## Step 0: Resolve mode, range, and changed files

One script does the whole of this step — mode detection, range normalisation and validation,
the changed-file list, the working-tree state, and the two commit logs:

```bash
~/.claude/skills/x-code-review/scripts/range-detect.sh [--repo PATH] [--range A..B] [--full]
```

**Read its `VERDICT:` line and its exit code — not the Bash tool's status.** Several of the
commands inside run mid-script, where the tool reports only the last one's status, so a
failure has no observable trace except the line the script prints for it (`(git diff exit=N)`).

| exit | `VERDICT:` | what to do |
|---|---|---|
| 0 | `ok` | go to **Step 1** (then Step 2), using the printed `PROJECT=` as the repo path and `Diff range:` as `<RANGE>`. Keep the `Mode:` line too — Step 3 and Step 4 both branch on it |
| 4 | `cross-repo` | go to **Step 1X**; the printed `PROJECTS:` list is its input — already absolute, and it has to stay that way through Step 2X, which runs in a subagent's own cwd |
| 3 | `no-changes` | genuinely nothing in range — inform the user and stop |
| 2 | `range-unresolved` | the range failed to resolve; say so and stop |
| 1 | `error` | the message names what to fix — an unresolvable ref, a tree-ish, `HEAD` on the left side, or a range given from a directory that merely *contains* repos |

**Pass `--repo` whenever cwd is not itself the repo, and always alongside `--range`.** The repo
comes from the caller, never from the refs: `origin/main` resolves in every repo of this
workspace, so ref names identify nothing. The script refuses to guess and lists the candidate
repos instead — answer it with `--repo`, do not infer from the branch name.

**A range is single-project by definition** (see the Parameters table); there is no cross-repo
form of it, which is why supplying one from a multi-repo directory is an error rather than a
fallback to Step 1X. Step 1X derives its own `BASE...HEAD` per project, so silently landing
there would discard the range and produce a confident correctness report about code the caller
never asked about.

---

# Single-Project Review

## Step 1: What the script decided, and the one check left to you

The range is already resolved and validated by Step 0's script. What it decided, so you can
read its output:

- **Range precedence** — an explicit `--range` wins outright; then `--full`; otherwise
  auto-detect (incremental if this PR has a prior review commit that is an ancestor of HEAD,
  else `BASE...HEAD`). Two-dot input is normalised to three-dot, because two-dot compares the
  two endpoints and once the left side has advanced past the branch point its own commits
  appear as inverted diffs.
- **Base** — the left side of an explicit range, else `origin/develop`, `develop`, `origin/main`, `main` (first that exists), or the remote HEAD branch. The `origin/` ref wins because the main clone's local branch is often unpulled, which would pull teammates' merged commits into the range; a `NOTE:` line says when the two differ.
- **Changed files** — printed **unfiltered**. Generated and lock files are excluded by the
  Step 2 subagent, not here: the exclusion patterns live in the coding-standards references,
  and Step 2 item 3 is the only place those get loaded. Filtering here would mean matching
  against a list this context has never read.

Two things the script reports but does not decide:

1. **The `=== Working tree ===` block.** What to do with it depends on the mode, which is why
   the script only states the fact:
   - **Explicit-range mode** — do not stop. A three-dot range compares two commits, so
     uncommitted work is never part of what gets reviewed; stopping would block every remote-PR
     review on an unrelated local edit, but staying silent is worse. Say `N uncommitted file(s)
     are not included in this range`, name them, and proceed.
   - **Auto-fix re-review (Step 4)** — expected; skip the check entirely.
   - **Otherwise** — a non-empty tree means the review would miss uncommitted work: tell the
     user and ask them to commit before re-running, then stop. An `ERROR: git status failed`
     line is not a clean tree, it is an unknown one — stop and say the command failed.

2. **Commit quality** — inspect the two commit blocks the script printed:
   - Flag any WIP / fixup / temp commits (messages like "wip", "fixup!", "squash!", "tmp",
     "test") that should be squashed before PR.
   - If the project uses conventional commits, flag commits in range that don't follow it.
     Judge the convention from the **`=== Base-branch commits ===` block the script already
     printed** — do not issue a fresh `git log`: there is no `BASE` variable in your shell, so
     it would expand empty and silently show HEAD's last 10 commits, which is the branch under
     review judged against itself.
   - **Do not stop** — continue to Step 2 and include commit quality issues in the final output.
   - **In explicit-range mode the commits are usually someone else's**, on a PR that is already
     open. Report them as an observation about that PR, not as an action for the user — "squash
     before proceeding" addresses a person who is not running this command and a branch that is
     past the pre-submission point.

## Step 2: Launch review subagent

Using the branch info and changed file list from Step 1, launch a single Agent tool subagent (subagent_type: general-purpose, model: sonnet) with the following instructions.

**Important**: Do NOT pass **diff content** into the subagent prompt — it collects that itself. What the prompt must carry:

- the **diff range**
- the list of changed filenames, said explicitly to be **unfiltered** (the subagent does its own generated/lock exclusion in item 1, and cannot tell a raw list from a filtered one by looking at it)
- **the repo's absolute path** — always, taken from the `PROJECT=` line Step 0's script printed. Every command in item 2 — the per-package fetch loop, `git show`, `git blame` — runs in the subagent's own cwd, and the script's own `cd` lived only inside that one Bash call. Whenever the repo sits in a subdirectory (Step 0's single-repo branch, and Step 3X's per-project loop) cwd is *not* a repo, so a bare `git` call there either fails or, worse, succeeds in the wrong repo. Step 2X already passes project paths for exactly this reason.
- **the absolute path `/Users/yijyun/.claude/skills/x-code-review/references/angles.md`** (write it out in full — every mention of `references/angles.md` below is shorthand for this path, and a subagent resolving the short form against the repo cwd finds nothing), with the instruction to read it before FIND. It holds two FIND angles, the sweep pass, and the re-review recheck; the subagent never sees this SKILL.md, so a criterion that lives only there and is not named in the prompt does not run.
- **in explicit-range mode: the four read commands of item 2 with both refs filled in** (`git show <right>:<path>`, `git show <left>:<path>`, `git blame <right> -- <path>`, `git grep <symbol> <right>`, with the actual ref names). Item 2 states the rule; this bullet is what makes it reach the prompt — `angles.md` defers to "the read mode the orchestrator gave you", and without it there is none.
- when this run is a **Step 4 auto-fix re-review**: that fact, **and every issue that survived the previous round as findings text** (not diff content, so the rule above does not apply) — withheld ones included, each tagged `withheld`. Tell the subagent to run the recheck section of `angles.md` in place of the sweep; that section carries the whole procedure, because the subagent cannot read this file. Without the list, a sweep-found or withheld issue is not looked for again, the count drops, and Step 4 reports success on an unfixed issue.
- when the caller is a PR review: **the PR reference as a runnable command** — `gh pr view <num> -R <owner>/<repo>` (gh does not parse `<owner>/<repo>#<num>`; it reads it as a branch name and fails) and any additional finding gates it requires. `x-pr-review` mandates that its eight verification gates ride along, and two of them cannot be evaluated without the PR — one quotes the PR description, one needs cross-repo evidence. Pass the reference, not the fetched body: the subagent runs `gh pr view` itself, which keeps this rule and the no-diff-content rule from colliding. **Those gates go into the prompt after this skill's own FIND/VERIFY/sweep instructions, labelled as additional gates on the survivors** — this bullet is where they arrive, not where they are placed. Putting them ahead of FIND/VERIFY reads as a competing verdict scheme and the subagent has to guess which one governs.

Instruct the subagent to:

0. **In explicit-range mode, item 2's read rule governs every item below, not just item 2** — the working tree is an unrelated branch everywhere. Item 1's generated-file content marker is read with `git show <right>:<path>`; item 3's `CLAUDE.md` / `docs/` files are found with `git ls-tree -r --name-only <right>` and read with `git show <right>:<path>`; item 4's directory listing is `git ls-tree --name-only <right>`. Otherwise a file the PR adds is checked against a tree that lacks it, and a rule finding cites the other branch's `CLAUDE.md`.

1. **Filter, then collect the diff.** The filename list you were given is **unfiltered**. First drop every file the "Generated & Lock File Exclusions" section of **`x-coding-standards`'s own SKILL.md** excludes — load that skill now, before anything else in this step. It is the canonical list and it is **not** in any `references/` file: item 3's reference loading is gated by language, so a TypeScript-only or Python-only diff loads zero references, and a filter sourced from them would quietly become no filter at all. That section carries two tests — a content marker for generated Go files and a filename regex (extended, not basic) for everything else — and both apply. Then run `git diff <RANGE> -- <file1> <file2> ...` using **only the surviving filenames** as pathspec arguments; never diff the entire range.

   If nothing survives the filter, the whole diff is generated or lock files. Report exactly that and stop — do not review generated output, and do not improvise a review of an empty set. (The orchestrator's empty-diff check — Step 0's script, via its `VERDICT: no-changes` — sees the raw list, so it cannot catch this case for you.)

   When the orchestrator says this run is a **Step 4 auto-fix re-review**, swap `<RANGE>` for the merge-base of **its own left side** — if `<RANGE>` is `X...HEAD`, run `git diff $(git merge-base X HEAD) -- <file1> <file2> ...`. That is one diff from the same starting point to the working tree, so the auto-fix subagent's uncommitted edits appear as the current code. `X` is whatever `<RANGE>`'s left side already is — `$BASE` in full mode, the last-reviewed commit in incremental mode. Read it off `<RANGE>`; do not substitute a different starting point. Substituting the base branch during an *incremental* re-review is the mistake this guards against: it would drag every earlier hunk in those files back in, inflate the count, and make the convergence check below report failure on a run that actually worked. Do **not** additionally diff `<RANGE>`: it is committed-only, so it would show the pre-fix line next to the fixed one, both looking current, and the review would re-report issues that are already resolved. Either mistake — omitting the working tree, or showing it alongside the committed range — makes Step 4's convergence check report "not converging" on every run.

2. **Read in two phases. Full reads are for the code under review, not for everything the diff touched.**

   An unconditional "read every changed file in full" is the dominant cost on a large PR and most of it buys nothing. Measured on an 81-file PR: 29,500 lines were in scope, of which the logic actually under review was 8,474 — the rest was 10,569 lines of test files, 6,534 of generator output the filter should have dropped, and ~3,900 of charts / docs / SQL / scripts.

   - **Phase A** — read **in full** every surviving non-test source file whose diff changes logic, **plus the unchanged files two of the criteria below require**: the 2–3 sibling files the *safety-pattern consistency* criterion compares against, and the `git blame` / history of the modified lines the *historical context* criterion reads. Those files are not in the diff, so "changed files" does not name them and neither does Phase B, which is candidate-driven — leaving them out of both phases silently retires two criteria. Phase A is the FIND pass's input and is not negotiable: a candidate built on a diff snippet alone is the shallow-finding failure the two-pass discipline exists to prevent.
   - **Phase B** — read a test, chart, migration, or doc **only when a candidate needs it as evidence**: the test that pins the invariant a candidate says is broken, the chart value a candidate says is wrong, the runbook a candidate says the code contradicts. Read those in full too — targeted, not skipped.

   **Do not cut by file kind.** The finding that survived the run this rule comes from had its strongest evidence inside a test file — the test's own doc comment stated the invariant, and its setup used a precondition that never reaches the defect, which is why the suite was green. A rule saying "skip tests" would have killed it. What Phase B drops is the tests no candidate touches; that is a different set.

   **Batch the reads: tool turns, not bytes, are what this costs.** Each turn re-bills the whole accumulated context, so 28 single-file `git show` calls cost far more than the same bytes fetched in a handful. Fetch Phase A **one package at a time** — a `for` loop over that package's files in one Bash call — rather than one file per turn; that is roughly 8 calls instead of 28 for a diff this size. When a file will be consulted again later, dump it to a scratch directory in the same loop so the second look is a local read instead of another `git show`. Do not try to fetch all of Phase A in one result: past ~20KB the output is persisted and you end up grepping it back in, which costs more turns than it saved.

   **In explicit-range mode, tell the subagent which refs to read at and that the working tree is not one of them** — the local checkout is on some unrelated branch, so the `Read` tool silently returns that branch's content and every finding built on it is wrong. Give it these four commands: `git show <right side of the range>:<path>` for the code under review, `git show <left side>:<path>` for the baseline, **`git blame <right side> -- <path>`** for the history criterion, and **`git grep <symbol> <right side>`** for every caller / callee / helper search (the `Grep` tool reads the working tree too). The blame and grep forms matter as much as the two `git show` forms — bare `git blame <path>` reads the working tree, i.e. the unrelated branch, so leaving it out means the *historical context* criterion either quietly retires or cites the wrong branch's history as evidence, and the second is worse than the first. Without all four, "read the files in full" reads as an invitation to open working-tree paths, which is the one thing this mode must not do.

**A single file over ~2000 lines is read in targeted regions, not whole.** Phase A being "not negotiable" fixes *which* files are in scope, not *how* each one is opened — for a very large file, follow the inherited read strategy (locate with grep, then read that region with its surrounding context) and say in the Coverage section which regions you read. In explicit-range mode locate with `git grep -n <sym> <right> -- <path>` and read with `git show <right>:<path> | sed -n '<a>,<b>p'` — the Grep and Read tools see the unrelated working-tree branch. Reading a 3000-line file in one shot collides with the same ~20KB persistence limit as batching does, and the recovery costs more turns than the batch saved.

3. **Read coding standards**:
   - Project-level: the repo-root `CLAUDE.md`, plus any `CLAUDE.md` in a directory that is an ancestor of a changed file (a directory's `CLAUDE.md` governs only files at or below it). Also `docs/`, `DESIGN.md`, `CONTRIBUTING.md`.
   - **The rule baseline is the project's own documents.** The user-level `~/.claude/CLAUDE.md` and `~/.claude/rules/*.md` are inherited into this subagent's context, but they govern how *you* work — not how this project's code must look. Do not raise a finding against them. Follow them only where the project's own `CLAUDE.md` explicitly adopts them (`arx-platform-proto/CLAUDE.md:3` defers language / git / Go standards to the global file; that deferral is what puts them in scope there).
   - **Language & interface references**: Invoke the `x-coding-standards` skill and load every reference whose condition the changed files hit — by language (Go `.go`, Helm chart `.yaml`) and by interface (HTTP handler, API request/response schema). A single `.go` handler hits both kinds.
   - Use these standards as supplementary review input.

4. **Explore project internal packages**:
   - First `ls` the project top-level directory structure to identify which directories are internal packages (do NOT hardcode `internal/`, `pkg/`, etc. — discover them).
   - When the diff introduces a new external dependency or creates a new utility function, search project internal modules to confirm no existing wrapper already provides the same functionality.

5. **Execute the review** applying the criteria below.

### Review criteria (apply these, not a hardcoded checklist)

**Scope: correctness and security only.** Quality, style, reuse, and efficiency
are owned by a separate cleanup pass — do NOT flag them here.

- Error handling completeness — missing rollback / resource cleanup that causes leaks or corrupt state (the *behavioral* gap, not error-wrapping style)
- Impact on callers — when the diff changes a function's error returns, parameter semantics, or return value contract, search for callers of that function and verify they handle the new behavior correctly. Flag callers that would break. Then the other direction: for each function the diff changes, check the calls it makes — does a parallel change elsewhere in the same diff (a callee's new precondition, a changed return shape, a reordered side effect) make an existing call unsafe?
- **Reachability change on existing lines** — an unmodified line is in scope when the change makes it newly reachable, or alters a precondition it relied on. Such a defect is caused by this change, not inherited from it. State which changed line creates the new reachability; a candidate that cannot name that line is pre-existing and out of scope.
  - Report: an existing parameter deref never checked for nil, where the diff adds a call path that passes nil into it.
  - Do not report: an unrelated off-by-one elsewhere in the same function, on a branch the change does not touch.
- Safety-pattern consistency — when the diff adds new code to an existing package, read 2-3 sibling files for established **safety** patterns (nil-guard checks on service dependencies, input validation before use). Flag new code that omits a guard its siblings apply. Example: if sibling service files check `if s.svc == nil { return ErrUnavailable }` before use, new service code must do the same. (Stylistic consistency — naming, error-wrapping style, interface-vs-concrete — is out of scope here.)
- **Historical context** — read the `git blame` / history of the modified lines. Flag changes that reintroduce a previously-fixed bug, contradict the reason the code was written that way, or drop a guard added by an earlier fix.
- **Code-comment compliance** — read comments in and around the modified code. Flag changes that violate a constraint or invariant those comments state.
- Any rule stated normatively in the project's **own** documents (`CLAUDE.md`, `CONTRIBUTING.md`, a standard under `docs/`) — reported under the FIND exception below, quoting the rule and the violating line. The `x-coding-standards` references loaded above are review *input*, not a rule source: a finding may not cite them, because they are conventions you brought, not rules this project adopted.

### Issue filtering standard

**SHOULD flag:**
- Compilation/syntax errors (missing imports, type mismatch)
- Clear logic errors (wrong condition, off-by-one, nil dereference)
- Clear violation of a rule stated in the project's own documents (never one of your own conventions)
- Security issues:
  - Input validation: SQL injection, command injection, path traversal
  - Auth & authorization: authentication bypass, privilege escalation
  - Secrets: hardcoded API keys, passwords, tokens in source
  - Code execution: unsafe deserialization, eval injection, XSS
  - Data exposure: sensitive data logging, PII leakage in API responses

**SHOULD NOT flag:**
- Style preferences (unless violating an explicit project rule)
- Issues that a linter / formatter would catch automatically
- Missing or thin test coverage, and suppression directives (`// nolint`, `#nosec`) without a justification — these belong to the project's own lint / CI pipeline, which can build and run the suite. This review only reads code, so any verdict it gives on them is weaker and slower than the tool's. Do not re-add them as criteria.
- Pre-existing issues (code NOT in the diff) — a defect this change made newly reachable is not pre-existing; it belongs to the reachability criterion above
- Code with lint-ignore directives that include a justification comment
- Subjective "could be better" suggestions
- DoS / rate limiting / resource exhaustion concerns
- Outdated third-party library versions (handled by dependency tools)
- Memory safety issues in memory-safe languages

### Additional review checks (apply as a FIND-phase angle)

- **The two angles in `references/angles.md`** — wrapper / proxy correctness, and language pitfalls (with its `go.mod` version check). Its last two sections, the sweep and the re-review recheck, run after VERIFY (Phase 3), not here.

- **Removed-behavior audit**: For every line the diff DELETES or replaces, name the invariant or behavior that line enforced, then search the new code for where it is re-established. If you cannot find it, that is a candidate. Reading only the `+` side can never surface this class — every added line is individually correct and the defect is the *absence* of a line. A candidate qualifies only with all three of: (1) the deleted line quoted with its `file:line`, (2) what it guaranteed, (3) where you searched and did not find it re-established — name the symbol you grepped and the files you read. A candidate missing (3) is unrefutable, so drop it here in FIND — do not pass it to VERIFY.
- **Silent failure detection**: Flag error handling that makes the code behave incorrectly — empty catch/except blocks swallowing an error the caller needs, error callbacks that do nothing, ignored return values from fallible operations (e.g., `_ = riskyOp()`), inverted error checks that skip the error path entirely (e.g., `if err == nil { use(result) }` instead of `if err != nil { return err }; use(result)`), an error that is only logged before execution continues as if the call succeeded, a default or zero value returned in place of an error the caller needed (e.g., `if err != nil { log.Warn(err); return Config{}, nil }`), and a retry loop that exhausts its attempts and then returns nil or nothing. For these last three, the failure scenario names the code that proceeds as if the call succeeded — the caller, or a later statement in the same function — and what goes wrong (e.g., a `Reconcile` that logs a failed status update and returns `ctrl.Result{}, nil`, so the object is never requeued). (Purely stylistic anti-patterns like un-wrapped `return err`, and logging *and* returning the same error, are out of scope here. The "either return or log" convention in `x-coding-standards` is style and never refutes one of these three.)

### Two-pass review: FIND then VERIFY (then Phase 3)

Run the review as **two distinct passes** — generate the complete candidate list first, then adversarially attack it (Phase 3 below adds a sweep or recheck after both; it does not merge them). Do NOT blend them: judging a candidate in the same breath you write it weakens the check (you end up defending your own reasoning instead of refuting it).

#### Phase 1 — FIND (surface, do not self-censor)

Generate every candidate defect for which you can name a concrete **failure scenario** — the specific input / state / timing that makes the code wrong.

**Do NOT filter by confidence here.** A finder that silently drops half-believed candidates (a race it's only ~60% sure of, a nil on a rare path) bypasses the verify pass below — and that silent drop, not lax verification, is the dominant cause of missed bugs. If you can name what breaks, surface it.

Every candidate MUST carry a `failure_scenario`: concrete inputs/state → wrong output/crash. The only candidates you drop in this pass are the ones you **cannot** write a failure scenario for — that inability is itself the false-positive signal.

**Exception — violation of an explicit project rule.** A documented-rule violation produces no crash, so requiring a crash-shaped `failure_scenario` would silently kill this whole criterion. Such a candidate carries two citations instead: the **rule text quoted with its `file:line`**, and the **violating line quoted with its `file:line`**. This is a stricter bar than a failure scenario, not a looser one — a quoted rule is verified by reading, with no trigger to infer. Two limits:

- The rule must exist in the project's own documents, stated normatively (`arx-platform-proto/CLAUDE.md:7-41` tabulates every rule with an RFC 2119 keyword — MUST / MUST NOT / SHOULD / MAY — and that keyword is what makes it quotable). Your own conventions are never the rule.
- Skip rules the project marks as tool-enforced. `arx-platform-proto/CLAUDE.md:54` states that when `buf lint` rejects something, the tool's error is the authoritative feedback — those fall under the "a linter would catch it" exclusion above. Only rules the project routes to manual review are yours to flag.

#### Phase 2 — VERIFY (3-state verdict, evidence required to kill)

Over the Phase-1 list: first dedup only true duplicates — **same defect, same location, same reason** (keep the one with the most concrete failure scenario). Two candidates on one line for different reasons are two findings: on `data[key] = val`, an unlocked concurrent write and a write to a nil map need different fixes (add a lock vs initialize the map), so merging them ships one fix and leaves the other in place. Then assign each remaining candidate exactly one verdict:

- **CONFIRMED** — you can name the triggering inputs/state and the resulting wrong output or crash. Quote the offending line.
- **PLAUSIBLE** — the mechanism is real but the trigger is uncertain (timing, env, config). State what would confirm it.
- **REFUTED** — factually wrong (code doesn't say that), provably impossible (type/constant/invariant — show it), or already guarded elsewhere (cite the guard). Quote the line that proves it.

For a **project-rule violation** (the FIND exception above), the three verdicts read off the two citations rather than a trigger: **CONFIRMED** when the quoted rule states what you claim and the quoted line breaks it; **REFUTED** when the rule text does not actually say that, when the project marks that rule tool-enforced, or when the project documents an exception that covers this code. There is no PLAUSIBLE tier here — a quoted rule leaves nothing uncertain to weigh.

**PLAUSIBLE by default.** Do NOT refute a candidate merely for being "speculative" or "depends on runtime state" when the state is realistic: concurrency races, nil/undefined on a rare-but-reachable path (error handler, cold cache, missing optional field), falsy-zero treated as missing, off-by-one on a boundary the code doesn't exclude, retry storms / partial failures, a regex/allowlist that lost an anchor. These are PLAUSIBLE, not REFUTED. Only REFUTE when you can construct the refutation from the code and quote the line.

Verify-specific checks (apply while assigning verdicts):

- **Stdlib / interface behavior claims**: before confirming a stdlib return value or interface contract is buggy, verify against the official Go documentation or interface definition and cite the specific contract. If the code follows the documented contract → REFUTED.
- **Caller-provided guarantees**: before confirming a missing guard (lock, mutex, input validation, context check, nil check), read the callers of the flagged function. If the caller already provides the guarantee → REFUTED (cite the caller line).
- Common false-positive patterns to catch here: "missing error handling" but the caller already handles it; "unused variable" but it's used outside the diff; behavior that is correct given broader module context; anything a linter/formatter would catch (out of scope — should not have been flagged).

**Keep CONFIRMED and PLAUSIBLE. Drop only REFUTED.**

#### Phase 3 — Sweep, or recheck in an auto-fix re-review

Run the matching Phase 3 section of `references/angles.md`: the sweep on a normal run, the recheck of the previous round's issues on an auto-fix re-review. Either way its candidates go through Phase 2's verdicts before joining the list. Any gates the caller supplied apply after this, to every survivor.

### Output format

Output only the surviving issues (CONFIRMED + PLAUSIBLE). Classify each by **severity** (Critical / High / Medium). Tag each with its verdict; PLAUSIBLE marks a real mechanism whose trigger the reviewer couldn't fully pin down, so the reader knows to weigh it. Each issue states its **failure scenario** (concrete inputs/state → wrong output/crash) — that is what makes it actionable. A project-rule violation states its two citations there instead: the quoted rule with its `file:line`, then the violating line. Its severity reads off the rule's normative keyword — **High** for MUST / MUST NOT, **Medium** for SHOULD / SHOULD NOT; never Critical, since a documented-convention breach does not break production. A rule written MAY states no requirement, so it has no violation to report.

**Semantic grouping**: When multiple issues share the same root cause or repeat the same pattern, merge them into a single item listing all affected locations instead of repeating as separate issues. Example: `[svc_a.go:42, svc_b.go:87, svc_c.go:15] (CONFIRMED) Service dependency used without the nil guard its siblings apply — a nil s.store panics on the first request after a failed init`.

```
## Issues

### Critical
- [file_path:line_number] (CONFIRMED|PLAUSIBLE) Description — failure scenario

### High
- [file_path:line_number] (CONFIRMED|PLAUSIBLE) Description — failure scenario

### Medium
- [file_path:line_number] (CONFIRMED|PLAUSIBLE) Description — failure scenario

## Fixed since last round        # auto-fix re-review only
- [file_path:line_number] <previous issue> — fixed by `<line>`

## Coverage                      # only when a file was read in regions (item 2)
- <file_path>: lines <a>-<b>, <c>-<d>

## Summary
One paragraph overall assessment. End with whichever recommendation matches the findings:
  - 0 surviving issues            → "Ready for PR"
  - any Critical or High          → "Address [N] high/critical issues before creating PR"
  - only Medium                   → "Address [N] medium issues before creating PR"
Never write "Ready for PR" while any issue survives — Medium included.
```

A **project-rule violation** goes under `### High` or `### Medium` (never `### Critical`, per the keyword rule above) and replaces the failure-scenario clause with its two citations, one per line:

```
- [file_path:line_number] (CONFIRMED) Description
  規則：<doc_path>:<line> 「<rule text, quoted verbatim>」(MUST|MUST NOT|SHOULD|SHOULD NOT)
  違反行：<file_path>:<line> `<the offending line, quoted>`
```

Omit severity subsections that have no issues. If there are no issues at all, output "No issues found." under the Issues heading. In an auto-fix re-review, an issue the fixer withheld keeps a `(withheld)` tag after its verdict — Step 4 item 1 reads that tag to skip it, so reproduce it as-is in Step 3.

**After** the Summary paragraph — not inside it — add one final line stating that FIND, VERIFY, and the sweep (or recheck) all ran inside this one subagent, so the verify pass re-checked its own candidates rather than an independent reviewer's. Keep it out of the paragraph: the paragraph's own last sentence must stay the recommendation, so a reader gets the verdict at the end of the assessment rather than after an aside. A reader weighing a PLAUSIBLE finding needs the independence disclosure; without it they will assume more than ran.

## Step 3: Present the result

Display the final review result to the user using **exactly** this format. Do not reorganize, add extra sections, or mix in your own commentary — present the subagent output as-is with only the adjustments noted below.

```
## Issues

### Critical
- [file_path:line_number] (CONFIRMED|PLAUSIBLE) Description — failure scenario

### High
- [file_path:line_number] (CONFIRMED|PLAUSIBLE) Description — failure scenario

### Medium
- [file_path:line_number] (CONFIRMED|PLAUSIBLE) Description — failure scenario
- [file_path:line_number] (CONFIRMED) Description          # project-rule violation
  規則：<doc_path>:<line> 「<rule text, quoted verbatim>」(MUST|MUST NOT|SHOULD|SHOULD NOT)
  違反行：<file_path>:<line> `<the offending line, quoted>`

## Fixed since last round        # auto-fix re-review only
- [file_path:line_number] <previous issue> — fixed by `<line>`

## Summary
(from review subagent, including its final independence line)
```

Omit severity subsections that have no issues. Keep the subagent's `## Coverage` section when it wrote one, just before Summary. Where a finding carries the two citation lines (rule text, violating line), reproduce them as the subagent wrote them — do not fold them back into a one-line summary.

**If Step 0's script reported `Mode: incremental`**, prepend a notice before the Issues section (the short hash comes from that same line — `Mode: incremental (since last review at <short-hash>)`):

```
⚠️ Incremental review: 僅涵蓋上次 review (commit <short-hash>) 之後的變更。
若新 commit 修改了先前 review 過的邏輯，建議跑 `/x-code-review full` 確認。
```

**If Step 1 found commit quality issues**, prepend them before the Issues section:

```
## Commit Quality

- `<hash> <message>` — reason (e.g., WIP commit, missing conventional prefix)

Recommendation: squash or reword before creating PR.
```

In explicit-range mode replace the last line with `Observation: these commits are on an open PR; squashing is the author's call.` — per Step 1, the commits there are someone else's.

After the review output, dispatch on the **surviving issue count** — not on the Summary's wording, so a mis-worded recommendation cannot decide the branch:

- If the subagent reported that **nothing survived the generated/lock-file filter** (Step 2 item 1), say exactly that: the diff was entirely generated output and **no review was performed**. Do not print the Issues template and do not say the code looks good — an unreviewed diff is not a passing review, and the 0-issue branch below would misreport it as one.
- 0 surviving issues: inform the user the code looks good. If there are uncommitted changes, remind them the changes are not yet committed — **except in explicit-range mode**, where Step 1's working-tree item already said those files are *not included in the range*. Repeating them here as "not yet committed" tells the user to commit someone else's-PR review leftovers, which is the opposite framing on the same files.
- 1 or more surviving issues (CONFIRMED or PLAUSIBLE, **any severity including Medium-only**), **and Step 0's script did not report `Mode: explicit range`**: use `AskUserQuestion` to offer:
  - **Auto-fix + re-review** — Proceed to Step 4 to fix issues and re-review automatically (up to 3 rounds total).
  - **Stop here** — End the review. The user will fix issues manually.
- 1 or more surviving issues **in explicit-range mode**: present them and stop. Say the findings are report-only for this run; do not offer auto-fix and do not enter Step 4.

The condition belongs in the bullet above and not in a paragraph after it, because an agent executing top-down would otherwise offer the choice before reaching the prohibition. The prohibition itself: Step 4's fixer edits the working tree, and an explicit range is normally two refs the local checkout is not sitting on (a remote PR's base and head). Fixing there writes someone else's changes onto whatever branch happens to be checked out, and the re-review then diffs a range that still cannot see those edits.

## Step 4: Fix and re-review loop

This step runs only when the user chose "Auto-fix + re-review" in Step 3. **Explicit-range mode never offers that choice** (see Step 3), so this whole step — including Step 2 item 1's re-review range arithmetic, which assumes `<RANGE>` ends in `HEAD` — does not run in that mode. Track the current round number (starting from 1, max 3).

1. **Before launching, drop anything a previous round already withheld.** The withhold rule below is deterministic, so re-sending a withheld issue buys nothing but a wasted subagent. Keep a withheld list across rounds. If every surviving issue is already on it, do not launch the subagent at all — go straight to item 2's outcome.

   Then launch an Agent tool subagent (subagent_type: general-purpose, model: sonnet) with:
   - The surviving issues (CONFIRMED + PLAUSIBLE) from the most recent review, minus the already-withheld ones
   - The list of affected filenames, **and the repo's absolute path** from Step 0's `PROJECT=` line — the filenames are repo-relative, and cwd is not the repo whenever it sits in a subdirectory or this runs from Step 3X's per-project loop; a bare path there fails, or edits a same-named file in a sibling repo
   - Instructions to read each affected file in full, then fix all reported issues while preserving functional behavior
   - **Withhold any issue whose fix would change a published interface** — a proto field or RPC name, an HTTP path, a schema key, a serialized format. List those for the user instead of auto-fixing them. This bites hardest on rule violations, which arrive CONFIRMED and often look like renames (`SetSshConfig` → `UpdateSshConfig` satisfies the rule and breaks every generated client), but it applies to any finding whose fix crosses a contract boundary.

2. If the subagent withheld **every** surviving issue because each one crossed a published interface, skip the re-review entirely — the working tree is unchanged by this round, so there is nothing new to see. Present the withheld list and stop, telling the user these need a deliberate contract decision rather than an auto-fix. From round 2 on, an earlier round's fixer has already edited the tree — list the build and test commands as in the all-clear branch below. Do not fall through to the convergence check below: it would report "not converging" about a fixer that was never given anything to do.

3. After the subagent completes, re-run Step 0's script to re-detect branch context (ignore the working-tree block — see Step 1 — and pass the same flags as the original run so the mode is preserved) and then Step 2 to re-review (which includes the Phase 2 VERIFY pass). **Tell the Step 2 subagent this is an auto-fix re-review, and pass it every issue that survived the previous round, withheld ones included and tagged** — the flag is what makes it pick up the working-tree fixes (see Step 2 item 1), and the full list is what keeps the count comparable across rounds (see the re-review bullet in Step 2). Count only the `## Issues` list; `## Fixed since last round` is not counted.

4. **Loop termination** — after re-review, check in order:
   1. **All clear**: If 0 issues survive (empty Issues list), present the result via Step 3. The re-review shows the fixes read right, not that they run: list the build and test commands the user should run before committing — from the repo's `Makefile` / `CLAUDE.md`, inside its devcontainer when the repo has `.devcontainer/` — and say they have not been run. Then stop.
   2. **Not converging**: Compare the surviving issue count with the previous round. If the count is equal or higher, stop immediately. Display the latest review result and inform the user: "Auto-fix is not converging (issues did not decrease). Please review the remaining issues manually." The fixer has edited the working tree, so also list the build and test commands as in the all-clear branch.
   3. **Round limit**: If the round limit (3) is reached and issues remain, display the latest review result and inform the user: "Reached the maximum of 3 auto-fix rounds. Please review the remaining issues manually." List the build and test commands here too, for the same reason.
   4. Otherwise, continue to the next round (back to step 1 of Step 4).

---

# Cross-Repo Review

Activated when the working directory contains multiple git repositories (e.g., worktree with multiple projects).

## Step 1X: Collect project context

For each project subdirectory that is a git repo:

```bash
for dir in <detected project dirs>; do
  echo "=== $dir ==="
  git -C "$dir" branch --show-current
  # Detect base branch per project; origin/ first, for the same reason as Step 0's script
  BASE=""; for b in origin/develop develop origin/main main; do git -C "$dir" rev-parse --verify -q "${b}^{commit}" >/dev/null && { BASE="$b"; break; }; done
  [ -n "$BASE" ] || BASE=$(git -C "$dir" remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
  if [ -z "$BASE" ]; then echo "ERROR: no base branch found for $dir — not skipping it as unchanged"; continue; fi
  echo "Base: $BASE"
  git -C "$dir" log --oneline "$BASE"..HEAD
  echo "--- Changed files ---"
  git -C "$dir" diff --name-only "$BASE"...HEAD
  echo ""
done
```

Pass each project's changed-file list on **unfiltered** — the Step 2X subagent excludes generated and lock files, for the same reason as the single-project path: the exclusion patterns are in the coding-standards references, which this context never loads.

A project that printed `ERROR: no base branch` is not empty — name it to the user as unreviewed; an empty `BASE` would have run `"...HEAD"`, which git answers with exit 0 and no output, so the project would have looked unchanged. Skip only projects whose **raw** diff is empty; if every project's raw diff is empty, inform the user and stop. A project whose diff turns out to be nothing but generated files cannot be detected here — Step 2X reports that one back after filtering.

## Step 2X: Launch mechanism review subagent

Launch a single Agent tool subagent (subagent_type: general-purpose, model: sonnet) with:
- The list of projects and their changed files from Step 1X
- The absolute directory path for each project
- **Each project's `Base:` value from Step 1X** — the diff in item 1 needs it, and the subagent cannot recover it: guessing `develop` for a `main`-based repo yields a wrong or empty range. Tell it to run every git command as `git -C <dir>`.

Instruct the subagent to:

1. **For each project**, filter first, then diff. **Invoke the `x-coding-standards` skill first** to get the "Generated & Lock File Exclusions" patterns — nothing else in this step loads them, and without them there is no filter. Drop every file matching those patterns, then run `git diff <BASE>...HEAD -- <file1> <file2> ...` with only the surviving filenames as pathspec arguments. Read all surviving files in full.

   Name any project left with zero files after filtering in your output (its diff was entirely generated or lock files) and exclude it from the flow analysis — the orchestrator could not detect that case. If **every** project is empty after filtering, report that and stop.

2. **Read project documentation** (`CLAUDE.md`, `DESIGN.md`, `docs/`) from each project to understand design intent. The user-level `~/.claude/CLAUDE.md` and `~/.claude/rules/*.md` are inherited into this subagent's context but govern how *you* work, not how these projects' code must look — never raise a finding against them.

3. **Trace the cross-service flow**: identify the request/data path across projects (e.g., API → Core → Manager). Map out how each project's changes contribute to the overall feature.

4. **Execute the review** focusing on mechanism-level concerns:
   - Flow completeness: Does the chain have gaps? Are all expected paths handled?
   - State consistency: State machines across services — are transitions complete? Can state get stuck?
   - Error propagation: When an intermediate step fails, does the error propagate correctly? Are there silent failures that break the chain?
   - Race conditions: Concurrent requests, TOCTOU issues, shared mutable state across async boundaries
   - Resource lifecycle: Goroutines that may never complete, connections not closed, context leaks
   - Timeout coherence: Are timeouts across services consistent? (e.g., caller timeout > callee timeout)

### Issue classification (mandatory)

Every finding MUST be classified into exactly one of:

| Classification | Definition | When to use |
|---------------|------------|-------------|
| **Defect** | Code does not match its own stated intent — a real bug | Logic errors, broken chains, unhandled error paths that contradict the code's own comments/design |
| **Design trade-off** | Code works as designed, but has a known trade-off | Intentional best-effort patterns, acceptable degradation, documented limitations |
| **Needs clarification** | Cannot determine from code alone whether this is intentional | Ambiguous behavior with no comment explaining rationale |

### Two-pass review: FIND then VERIFY

Same FIND-then-VERIFY discipline as the single-project path — generate the full candidate list first, then verify. Do NOT self-censor during FIND. The extra angles, sweep, and recheck in `references/angles.md` are deliberately not part of this mechanism-level pass; they run when Step 3X's per-project review is accepted.

#### Phase 1 — FIND (surface, do not self-censor)

Surface every candidate mechanism defect for which you can name a concrete **failure_scenario** — the cross-service sequence (request path, state, timing) that breaks the chain. Do not drop a candidate for being only half-believed; the verify pass is what filters. The only candidates you drop here are the ones you cannot write a failure scenario for.

**Removed-contract audit (across the seam).** For every contract element one project's diff deletes, renames, or narrows — a proto field, an RPC, a schema key, a response field, an env var — find where the consuming project stops depending on it or re-establishes it. Cite both sides' `file:line`; if the consumer still reads the old element, that is a candidate. Each project can be internally consistent while the seam between them is broken, so reading one project at a time never surfaces this.

#### Phase 2 — VERIFY (3-state verdict → output bucket)

First dedup only true duplicates — **same defect, same location, same reason**. Two candidates on one seam for different reasons are two findings: a response field the producer renamed and a timeout the producer shortened both break the same call, but need different fixes. Then re-read the referenced files and surrounding context for each remaining candidate and assign a verdict — which decides its output section:

- **CONFIRMED defect** → **Defects**. You can name the triggering sequence and the wrong outcome. Quote the line. Contradicting the code's own stated intent (a comment, a design doc) is *one way* to establish this, not a requirement — an undocumented bug is still a bug, and demanding a stated intent to contradict would push every defect in uncommented code into Needs Clarification and leave Defects empty.
- **PLAUSIBLE** → **Needs Clarification**. The mechanism is real but you can't confirm from code alone whether the trigger is reachable or intended. State what would confirm it. **Do NOT silently drop these** — an unverifiable-but-real mechanism is exactly what the author must confirm.
- **Intentional by design** → **Design Trade-offs**. A cited comment / guard / fallback shows the behavior is deliberate: best-effort / fire-and-forget (e.g. power commands that must not block), timeout/stale-detection recovery, caller-controlled input range. Cite it.
- **REFUTED** → drop. Factually wrong (quote the line), or requires multiple simultaneous failures the code's guards already prevent (cite the guard).

**PLAUSIBLE by default.** Do not demote a real mechanism out of Defects merely because its trigger depends on runtime state (concurrency, cold path, partial failure). Demote only when you can cite the design comment/guard that makes it intentional, or prove the trigger impossible. When unsure between Defect and intentional → **Needs Clarification**, never a silent drop. (Mechanism-review false positives are costly across services — so the bar to REFUTE or call something intentional is "cite the evidence," not "feels designed.")

### Output format

```
## Cross-Repo Mechanism Review

### Projects
- project-a (N files changed)
- project-b (N files changed)

### Flow
Brief description of the cross-service flow.

### Defects
- [project/file_path:line_number] Description — why this is a bug
  counterpart: [project/file_path:line_number]        # seam findings only — the other side of the contract

### Design Trade-offs
- [project/file_path:line_number] Description of the trade-off — impact and under what conditions
  cited as deliberate by: [project/file_path:line_number] <the comment / guard / fallback>

### Needs Clarification
- [project/file_path:line_number] Description — what is ambiguous and what the two possible interpretations are
  counterpart: [project/file_path:line_number]        # seam findings only — the other side of the contract

### Summary
Overall mechanism assessment.
```

Omit sections that have no items. If there are no Defects, explicitly state "No defects found."

The Summary MUST close by stating that FIND and VERIFY both ran inside this one subagent, so the verify pass re-checked its own candidates rather than an independent reviewer's — the same disclosure the single-project path makes, and for the same reason: a reader weighing a Needs Clarification item needs to know how much independence stands behind it.

## Step 3X: Present the result

Display the review result as-is from the subagent (candidates already verdict-sorted by the VERIFY pass). Keep Design Trade-offs and Needs Clarification as-is.

After the output, prompt:

> 要對各專案分別跑 per-file code review 嗎？

If the user accepts, run **Step 0 → Step 3** (Single-Project Review) sequentially for each project that has changes. Per project, pass that project's **absolute** path as `--repo` to Step 0's script — that is the only change. Do not omit it: in cross-repo mode cwd is not a repo, so the script would run its own mode detection from here and come straight back with `VERDICT: cross-repo`.
