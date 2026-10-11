---
name: x-cc-release-cfg-sync
description: "Sync Claude Code config with release note changes. Trigger on: '/x-cc-release-cfg-sync', upgrading Claude Code, 'what changed in Claude Code', or auditing config against recent releases."
model: sonnet
---

# CC Release Config Sync

Analyze Claude Code release notes and sync your configuration accordingly.

## Arguments

| Format | Behavior |
|--------|----------|
| (none) | From the last reviewed version to the installed version (fallback: last 5 versions) |
| `<from>` | From `<from>` to the installed version |
| `<from> <to>` | Specified range, capped at the installed version |

Example: `/x-cc-release-cfg-sync`, `/x-cc-release-cfg-sync v2.1.85`, `/x-cc-release-cfg-sync v2.1.85 v2.1.91`

Two properties of `<from>` to state when reporting, because neither is what the words suggest:

- **`<from>` is exclusive.** It names the last version already reviewed, so `v2.1.85 v2.1.91` covers v2.1.86–v2.1.91. A user who means "start at v2.1.85" has to pass v2.1.84.
- **The range cannot cross a minor version.** `v2.0.50 → v2.1.10` is a hard `error` — patch numbers of the earlier minor line can't be enumerated. This is the likely shape of the first run after a minor bump, so route it to the CHANGELOG fallback rather than treating it as a bug.

---

## Workflow

### Phase 1+2: Resolve Range and Fetch Release Notes

Run the script. It resolves the installed version, both ends of the range, and the version cap, then fetches each version's release body:

```bash
python3 ~/.claude/skills/x-cc-release-cfg-sync/scripts/fetch-releases.py \
  --out /REPLACE/WITH/SCRATCHPAD/cc-notes     # --out is required
# add --from v2.1.241 / --to v2.1.251 only when the user named a range
```

Replace the whole `--out` path with this session's scratchpad directory, then check the `OUT:` line the script echoes back names the directory you meant. Do not write a shell variable there: an unset `$VAR` expands to nothing and the run quietly targets a different directory, whereas the literal above fails loudly because it cannot be created.

Omit `--from` to continue from `.last-reviewed`; omit `--to` to end at the installed version. Each version's notes land in `<out>/v<version>.md` — read those files rather than re-fetching. The `READ:` block lists them and says how to read them. A wide range is slow (one sequential API call per version; ~250 versions takes over two minutes), so run it in the background when the range is large.

**Read the `VERDICT:` line; it decides what the report may claim.**

| VERDICT | exit | What it means and what to do |
|---------|------|------------------------------|
| `ok` | 0 | Every version in the range returned substantive notes. Proceed. |
| `unavailable` | 2 | Ran, but the COVERAGE table lists versions with no analysable content (`missing` = no release tag, `empty` = tag with empty body, `boilerplate` = body says only "Bug fixes and reliability improvements"). Proceed, but the report header **must** name those versions as unanalysed — see the Coverage line in the output format. |
| `error` | 1 | Usage error, unresolvable range, or a fetch failed. Two messages need distinct handling: `UP TO DATE` means `.last-reviewed` already equals the range end — tell the user there is nothing new and stop. `FETCH FAILED` names versions that do have notes but could not be retrieved (403 / rate limit / network) — never describe those as content-less and never let `.last-reviewed` move past them; retry or use the CHANGELOG fallback. |

The COVERAGE table is the report's coverage claim. Copy the version counts from it rather than counting the range's width — a run over 10 versions where 5 have no body is a report about 5 versions.

**Fallback** — for the two `error` causes the script cannot resolve on a retry: a range spanning minor versions, and `FETCH FAILED` from API failure or rate limiting. Fetch the full CHANGELOG (~1MB) and extract the relevant sections, or ask the user to paste the release notes text. (`UP TO DATE` is not one of these: stop and say so.)
```
https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
```

### Phase 3: Identify Affected Config Areas

Scan the extracted release notes and tag each change with the config areas it affects:

| Signal in release notes | Config area | Files to read |
|------------------------|-------------|---------------|
| New/changed settings fields, default value changes | settings | `~/.claude/settings.json` |
| Tool behavior changes, permission syntax changes | rules | `~/.claude/rules/**/*.md` (only rules referencing the affected tool) |
| Skill description limits, tool capability changes | skills | `~/.claude/skills/*/SKILL.md` (only affected skills) |
| Hook events, hook syntax, hook fields | hooks | hook scripts referenced in `settings.json` |
| Statusline JSON input fields, rendering changes | statusline | statusline script referenced in `settings.json` |
| New config directories, new file types | new mechanisms | (flag for user attention) |

Only proceed to read files in areas that have at least one matching change. Skip unaffected areas entirely.

### Phase 4: Read Affected Config

Based on Phase 3 tagging, read only the relevant files in parallel.

For settings.json: always read (almost every release touches settings behavior).

For rules/skills: read only files whose content relates to the changed features. Use Grep to locate relevant files before reading full content:
- Tool behavior change for "Edit" → Grep rules/ for "Edit" references → read matching files
- Skill description limit change → read all SKILL.md frontmatter (just first 10 lines each)

For hooks/statusline: extract file paths from settings.json, then read those files.

**Two methods that beat reading the release note again when a field's real shape or a config field's support is in question:**

- **Capture the statusline's real stdin.** Add one temporary line after the script's `input=$(cat)` writing `"$input"` to a scratchpad file, let one turn render, read the JSON, then remove the line. This is the one edit allowed before Phase 6's confirmation gate, because it changes no behaviour and Phase 4 is not done until the line is gone — say in the report that you added and removed it. It gives the exact field names and which optional fields are actually present for this user's model — release notes name new fields but not their shape, and a field documented as conditional ("appears only when…") can only be settled by looking.
- **Delegate documentation questions to a `claude-code-guide` subagent, requiring a doc URL plus a quoted line per answer.** Use it for whether a settings/hook field is supported, what a new stdin field contains, and what a warning's exact trigger condition is. Ask it to say "undocumented" rather than guess, so an undocumented answer routes to a live probe instead of into the report as fact.

### Phase 5: Analysis & Output

For each change, compare against the config read in Phase 4. Classify into two groups:

**Group 1 — Existing Config Impact**: Changes that affect files you already have. Behavior changes, default value shifts, syntax changes, bug fixes that alter how your current settings/rules/hooks/statusline work. The user needs to know: does my current setup still work correctly?

**Group 2 — New Opportunities**: New settings, new hook events, new config mechanisms, new capabilities worth adopting. Things the user doesn't have yet but might want. The user needs to know: is there anything new worth adding?

Within each group, explain each item with:
- What changed (one line)
- Which file is affected (or "new" if it doesn't exist yet)
- **How you know** — the check that settles it, written out for **every** item, not only the ones that feel uncertain. For most items this is one clause ("settings.json has no such key", "your model is `opus[1m]`, this is gated to Sonnet 5"). Writing it for every item is what makes the next rule checkable: an item with no check written down has nothing to gate on, and that is exactly the item that quietly ships unverified.
- What to do (no action / consider adding / the result of the check)

Then read the check you just wrote for each item. **An item may ship with a ⚠️ only if that check needs something this session cannot do** — a fresh interactive session, another machine, a config change the user has not approved, or the user's own eyes. Everything else runs now, and the item carries its result instead of a request. One Bash call, one file read, or one subagent question is not a reason to hand the work back.

Report the observation, not the flag: "三個探針都直接執行、沒有跳出核可提示" with the commands and their output, not "已驗證".

**New model in the range**: when any version's notes add a Claude model (a line like "Added Claude Opus 5.5 (`claude-opus-5-5`)"), add a fixed Action Item: the user runs `/doctor prompt-audit` (available from v2.1.283). It audits CLAUDE.md files, skills, agents and commands for prompting patterns written for older models, and a model release is exactly when those patterns go stale. It is a built-in command that only the user can type — the Skill tool cannot invoke it — so the item carries ⚠️.

**Filtering & consolidation**:
- Skip changes irrelevant to the user's environment (determined by reading actual config)
- Bug fixes and changes that don't affect the user: **consolidate into a single summary line per file**, not listed individually. Example: "另有 3 個 bug fix（PostToolUse format-on-save、hook output >50K、compound command matching）不影響現有設定"
- Only list items individually when they need user action or awareness of a behavior change

**Language**: Output in the user's system language setting. Follow the project's communication rules for language choice.

**Output format** (illustrative only: the versions, setting keys, plugin names and counts below are not facts about this machine; do not copy them):

```markdown
## CC Release Config Sync: v{from} -> v{to}

**Installed**: v{installed}
**Analysed**: {N of M} ({versions with status `notes`})
**No content**: {versions the COVERAGE table marked missing/empty/boilerplate, with why} — 這幾版無法分析，下面的結論不涵蓋它們
**Capped**: {the script's CAP: line, if it printed one}

### 現有配置影響

**settings.json**
- [v2.1.89] `showThinkingSummaries` 預設改為 false — 你沒有設定這個值，所以 thinking summary 現在是關閉的。需要的話加 `"showThinkingSummaries": true`
- 另有 2 個 bug fix（cleanupPeriodDays 驗證、symlink 解析）不影響現有設定

**rules/file-operations.md**
- [v2.1.89] Edit 現在可以在 Bash 瀏覽過的檔案上直接操作，不需要先 Read — 你的 rule「Never Edit without Reading first」仍然是好的 guardrail，不需修改

（按檔案分組。沒有相關變更的檔案不列出。不影響的 bug fix 合併為摘要行。）

### 新功能 / 值得採納

- [v2.1.89] **`"defer"` hook decision** — 讓 headless session（`claude -p`）在 tool call 時暫停等待審核。你的 settings.json 只有一個 PreToolUse hook 且沒有 headless 用途，所以目前沒有東西會用到它
- [v2.1.91] **Plugin `bin/` executables** — plugin 可以附帶執行檔。你啟用了 2 個 plugin（skill-creator、gopls-lsp），兩者的 plugin.json 都沒有 `bin` 欄位，所以現況不受影響
- [v2.1.91] **`disableSkillShellExecution`** — 限制 skill 中的 shell 執行。文件寫的涵蓋範圍是 skill 內的 shell 而非整個 session（doc 引文附上）；你有 14 個 skill，其中 6 個的流程會用到 Bash，要不要開由你決定
- [v2.1.91] **啟動時的 allow rule 警告** — ⚠️ 這項要你自己看：警告只在互動式 session 啟動時印一次，這個 session 已經起來了，開一個新的看有沒有那行

（每個項目自成一體。⚠️ 只給這個 session 做不到的檢查——需要全新 session、另一台機器、使用者的眼睛，或一個使用者還沒同意的設定變更；其餘一律先跑完再寫進報告。注意第一項為什麼不用實際開啟設定就能寫：它靠文件引文加上讀自己的 skill 目錄，兩者都不動使用者的 config。）

### Action Items
- [ ] Item 1 (file: path)
- [ ] Item 2 (file: path)
```

Wait for user to confirm which items to proceed with. Do not edit files until explicit confirmation.

### Phase 6: Execute Changes

After user confirms:
1. Execute changes one by one
2. For a ⚠️ item the user came back with an answer on: implement based on their answer, not on the release note's wording
3. After all changes: list every file touched and what changed in each. `~/.claude` is not a git repository, so there is no diff to run — the change set is whatever you state, which is why it has to be stated per file
4. Update the last-reviewed marker — **only after a run that ended `ok` or `unavailable`**:
   ```
   Write("~/.claude/skills/x-cc-release-cfg-sync/.last-reviewed", "{to_version}")
   ```
   `unavailable` is safe to write past: its gaps are versions with no tag, an empty body, or boilerplate only, and re-fetching them later returns the same nothing. A `FETCH FAILED` run is not — writing the marker there closes off versions whose notes were never read, and the default `(none)` invocation will never come back to them.

---

## Constraints

- **Never recommend features beyond the installed version.** Exclude or label as "requires upgrade to v{version}"
- **Read actual files, don't assume.** Always read current config state in Phase 4
- **Discussion before execution.** Phase 5 is for discussion only. Edits happen in Phase 6 after confirmation — the sole exception is Phase 4's statusline stdin probe, which must be removed within the same phase
- **Targeted reads.** Don't read all config files — only those affected by the release notes (Phase 3 filtering)
- **One change per concern.** Identify the single most appropriate file to modify, don't scatter related changes
