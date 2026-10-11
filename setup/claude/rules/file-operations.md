# File Operations

## Read Strategy

| File Size | Strategy |
|-----------|----------|
| < 500 lines | Read fully |
| 500-2000 lines | Config/yaml/json → full; code needing full context → full; large .md → `grep -n '^#'` then read the needed sections in full, or the whole file if unsure which; specific function → offset/limit |
| > 2000 lines | `grep` to locate first (`^#` for .md, symbol for code), then read that region with its surrounding context |
| Persisted tool output (>20KB) | Need a slice → `grep` the target lines, then offset/limit around them. Need the whole file → do NOT re-run the command that produced it; redirect its output to a scratchpad file and Read that (for a review reading several `git show <ref>:<path>` versions, dump them all in one loop first) |

- **使用者給了一個沒見過的路徑 → 先 `ls` 父目錄並讀該目錄的 `README`**：那個路徑預設是「去讀的慣例」，不是「要建的檔案」。判準是外顯的——這個路徑我這輪還沒讀過——不必先判斷使用者是什麼意思。父目錄的 README 通常就寫著這裡放什麼、誰會清掉它。
- **No re-reads**: Use context for already-read files. Re-read only after Edit/Write or context compression — a *different offset* of a file you already opened is NOT a fresh read; if you'll need more than one slice, grab them in one pass (small file → whole; large file → the region you need per the size table, but read it once).
- **Parallelize**: Independent tool calls (reads, searches, git commands) in a single message. Common patterns: multi-repo status checks (`git status` / `git log` across repos), post-deploy verification (`kubectl get hr,kustomization,gitrepository -A` together), Reading several known paths, exploratory grep across multiple patterns or directories
- **Tracing → read once, not per-symbol slices**: When tracing symbols across files (review / root-cause / call-chain), the cost multiplier in an agentic loop is *tool turns*, not bytes — each turn re-bills the whole accumulated context. Read each relevant file's needed content **once** and keep it in context — for a < 500-line file that means whole (the rule applies to `git show <ref>:<path>` baseline reads too; huge files still target sections per the table, but read that region once). Don't loop grep→narrow-show per symbol on the same file (that turns one file into 4–5 turns); grep is a one-time locator for an unknown file — on a hit, read it, don't re-slice.

## Edit/Write Discipline (mandatory)

**Never Edit/Write a file without viewing it first**, regardless of batch size.
The Edit and Write tools enforce this themselves — they refuse a file not Read in
this conversation — so a grep never substitutes for the Read there.

When editing through Bash instead (`sed -i`, a python script), nothing enforces it.
The requirement is having enough context to edit correctly:

- A single-file `grep`/`egrep`/`fgrep` that already surfaced the exact lines and their surrounding context is enough.
- Read first when grep output is insufficient: multi-file greps, or when the edit depends on context beyond the matched lines (indentation, nearby blocks, file structure).

## Batch Error Fixing

1. Collect all errors from tool output
2. Parallel-read all affected files
3. Merge fixes per file into one Edit
4. Re-run tool to verify all fixed

## Edit Behavior

- **Success** → next Edit uses post-edit content, no re-Read needed
- **Failure** → re-Read to check current state
- **Rejected** → STOP, clarify with user

## Search Strategy

- **Simple patterns first**: Search for function/method definitions with `func.*MethodName` — don't try to match full signatures with receivers, generics, or complex parameter lists
- **Long structured matches**: When the hit is one huge line (JSONL, minified JSON, etc.), use `python3 -c` to parse and extract the needed fields — do not retry with Read or a narrower grep
- **Cross-repo tracing**: When tracing a call chain across multiple repos, start with parallel `grep` in all repos to locate entry points, then Read only the relevant files. Do not spawn one Explore agent per repo — the search target is usually specific enough for direct `grep` + Read

## Multi-location Edits

- **`grep` first**: Scan all target locations before editing
- Pure rename → `replace_all: true` (perform substring check below first)
- Locations < 50 lines apart → merge into one Edit
- Locations > 50 lines apart → separate Edits

### `replace_all: true` substring check (mandatory)

Before running `replace_all`, `grep` `old_string` across the target file:
- Are matches **standalone identifiers** (intended changes) or **substrings of longer identifiers** (potential accidental matches)?
- If the latter: should the longer identifier also be renamed? Will the new name collide with existing names (compile errors, duplicate test helpers, etc.)?
- When in doubt → use multiple specific Edits instead of `replace_all`

Example: `FirmwareManager` → `Manager` via `replace_all` would also catch `newTestFirmwareManager` → `newTestManager`; if another file already has `newTestManager`, this triggers a naming collision.
