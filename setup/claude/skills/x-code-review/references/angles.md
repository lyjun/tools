# Extra FIND angles, the sweep pass, and the re-review recheck

Read by the Step 2 review subagent. The orchestrator passes this file's path; nothing else in the
subagent's context carries this text — the subagent never sees x-code-review's SKILL.md.

All reads and searches below follow the read mode the orchestrator gave you. In explicit-range
mode the working tree is an unrelated branch, so: read files with `git show <right side>:<path>`,
search with `git grep <symbol> <right side>`, never the `Read` or `Grep` tools. A working-tree
read there returns another branch's code, and a working-tree search finds callers that do not
exist in the PR and misses ones that do.

## Angle: wrapper / proxy correctness

Applies only when the diff adds or modifies a type that wraps another (cache, proxy, decorator,
adapter, retrying or metrics client). Check two things:

- Every method routes to the wrapped instance, not back through a registry, session, or global.
  A caching provider holding a `delegate` field that resolves IDs via a package-level lookup
  instead of `delegate.Get(...)` re-enters the cache or recurses.
- The wrapper forwards every method the callers actually use. Search the callers of the wrapped
  interface; a method they call that the wrapper does not override silently bypasses it (Go
  struct embedding makes this compile cleanly).

## Angle: language pitfalls the diff introduces

Flag only instances the diff introduces, each with its failure scenario.

- **Go**: write to a nil map (a struct field map never initialised on one constructor path);
  float `==` comparison; `time.Now()` / `time.Local` where the stored or compared value is UTC,
  or a duration computed across a DST change; a `defer` inside a loop that holds a resource until
  the function returns; a value-receiver method that mutates a copy.
  **Loop-variable capture**: first read the `go` directive of the nearest `go.mod` above the
  changed file, at the reviewed ref (`git show <right side>:<path>/go.mod` in explicit-range
  mode — the PR may be the one that bumps it). At `go 1.22` or later each iteration has its own
  variable, so capture is not a bug — do not flag it.
- **Other languages in the diff**: the classic pitfalls of that language (JS falsy-zero and `==`
  coercion; Python mutable default arguments and late-binding closures; shell unquoted
  expansion; SQL string concatenation).

## Phase 3, normal run: sweep pass

Runs after Phase 2 VERIFY. **Not in an auto-fix re-review** — that run does the recheck below
instead; sweeping there adds new candidates every round and makes the convergence count
meaningless.

Take one more pass holding the verified list. Re-read the diff and enclosing functions looking
**only** for defects not already listed — do not re-derive or re-confirm anything already there.
Focus on what the first pass tends to miss:

- moved or extracted code that dropped a guard, an anchor, or an error branch
- lock scope shrunk, or a check and its use split across the lock boundary
- predicate / getter methods with side effects
- config defaults flipped, or a zero value that now means something different
- the deleted blocks, and the largest **surviving non-test source file**, read once more — that
  is where a first pass most often stops early

Each sweep candidate needs the same `failure_scenario` as a FIND candidate and then goes through
Phase 2's three verdicts. If nothing new survives, add nothing — do not pad.

## Phase 3, auto-fix re-review: recheck of the previous round's issues

Runs only when the orchestrator says this is an auto-fix re-review; it then also hands you the
previous round's surviving issues, some tagged `withheld` (the fixer deliberately did not touch
them because the fix crosses a published interface). Run it after Phase 2 VERIFY of this
round's FIND candidates, in place of the sweep:

1. For each previous issue, re-run Phase 2's verdict against the **current** code (the
   working-tree diff from item 1) — do not carry the old verdict over; a half-applied fix can
   turn CONFIRMED into REFUTED or leave it CONFIRMED with a different line.
2. REFUTED now → it is fixed. List it under `## Fixed since last round` (one line each, with the
   line that fixes it), placed after `## Issues` and before `## Summary`.
3. CONFIRMED or PLAUSIBLE → still present. Dedup it against this round's FIND survivors with the
   same rule as Phase 2 (same defect, same location, same reason → one issue), then put it in
   `## Issues` with its verdict. Keep a `withheld` tag on the entry if it had one.

The orchestrator compares the `## Issues` count across rounds, so every still-present issue must
be in it exactly once, and nothing in `## Fixed since last round` may be in it.
