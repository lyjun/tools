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

## Angle: guarantees the change relies on

Applies when the diff puts new behaviour behind an earlier step's success — a new call after
`if err != nil { return }` on that step, after a boolean it returned, or after a loop that is
meant to have cleaned something up — or when a comment the diff adds says another function has
already ensured something ("X has taken Y out by now"). The new code is right only if that
guarantee holds on every path where the earlier step reports success. Those paths usually sit
in lines the diff does not touch, so reading the `+` side never shows them, and a reviewer who
reads the comment tends to repeat it as a fact.

1. Name the guarantee in one sentence, and the function meant to provide it: the one whose
   result the new code tests (the call whose `err` or return value the gate checks), not a
   helper a comment or your own reading credits with the work. Start the path list there.
2. List every path on which that function reports success — each `return nil`, `return true`
   or normal return, and each `continue` or early exit that skips an element of the loop doing
   the work — with its `file:line`. Follow the work into every function it delegates to, until
   each path either establishes the guarantee or does not: listing only the outer loop misses an
   early `return nil` inside the helper it calls.
3. Against each path, write whether the guarantee holds there and the line that makes it hold.

A path where it does not hold is a candidate. Its failure scenario is the state that takes that
path, followed by what the new behaviour then does to it.

Whether or not the trigger above matched, the same list is owed when a guarantee is used to clear
a concern: when a VERIFY verdict, the Summary, or a "checked and found fine" note dismisses
something because "X guarantees Y", it cites the path list from step 2 for X. That includes
VERIFY's "already guarded elsewhere" and "the caller already provides the guarantee": when the
guard is another function's success rather than a check on the flagged line, one cited line does
not refute. A dismissal that rests on the guarantee without the list is an unchecked claim — keep
the candidate PLAUSIBLE instead of dropping it; where no candidate was raised, write the claim as
a row in `## Relied-on guarantees` marked `not listed — unchecked`, so the reader sees it was
never checked.

Write the list in the output's `## Relied-on guarantees` section whenever this angle applied or a
dismissal rests on a guarantee, including when every path holds, so the reader can check the
paths you counted.

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
