---
name: x-pr-review
description: Unified code/PR review entry — (1) self-review of your own code or PR before submission, (2) first review of someone else's PR, (3) confirming a PR author's responses to your earlier review comments. Covers problem/solution comprehension, baseline setup, design critique, correctness/security (delegated), and reply confirmation. Read-only: produces a findings report for you to weigh; never auto-posts or edits. Use whenever the user says "review my code/PR", "幫我 review 這份改動", "review PR", "幫我 review PR", gives a PR URL with review intent, or asks to verify an author's replies ("同事回覆了幫我看", "確認作者有沒有處理到"). Always invoke for review requests even without "x-pr-review".
model: sonnet
---

# Review

Unified review entry covering three cases. **Read-only**: this skill produces an
internal findings report for *you* to weigh — it never posts to the PR or edits
code. Posting a review is a separate, explicit step (see Output model below and
`references/publish-format.md`). It performs exactly two writes, both to git plumbing
rather than to any repo's contents, and both announced when they happen: **cloning** a
repo the review needs and has none of locally, and **fetching a fork PR's head into a
local `pr-<num>` branch ref** — the second lands inside an existing clone, so it is not
covered by announcing the first. No file in any repo is edited.

## Step 0: Dispatch — determine the case first

Run the dispatch probe first — one query block resolves **both** ownership and whether this is a reply-confirmation. A bare PR URL carries neither signal in the message; both live on the remote PR, so probe before deciding:

```bash
python3 ~/.claude/skills/x-pr-review/scripts/pr-state.py <owner>/<repo>#<num> [--repo <local path>] [--checks]
```

`--checks` 加印 head commit 的 live CI:每桶的數量、還在跑的名字、失敗的名字,以及 `CHECKS_SETTLED`。**要 approve 之前跑一次帶 `--checks` 的**——PR 描述寫「測試全綠」講的是某個更早的 commit,這一欄講的是 head 現在回報什麼。它只量不判:查詢失敗、或列到的 run 少於 API 自己的 `total_count`、或這個 commit 上根本沒有任何 check,一律報 `CHECKS: unavailable` 並讓整體 VERDICT 跟著 unavailable——空答案不准讀成乾淨的答案。

It reports, in this order, `STATE`, `IS_DRAFT`, `AUTHOR`, `ME`, `ME_ENGAGED` (checked across
review bodies, issue comments **and** inline review comments), `ENGAGED_AT`,
`ENGAGED_EXCERPT` (the first line of my last trace — enough to tell a real
review from a drive-by question), `REVIEWED_SHA`, `HEAD_SHA`, `HEAD_CHANGED`,
`REVIEWED_SHA_REACHABLE`, `REPLIES_AFTER_ME`, `FROZEN`, and — only with `--checks` — `CHECKS` / `CHECKS_PENDING` / `CHECKS_FAILING` / `CHECKS_SETTLED`. `FROZEN` is recomputed from
`STATE` / `ME_ENGAGED` / `HEAD_CHANGED` / `REPLIES_AFTER_ME`, answering whether this PR's code
can still change. **It emits no case label**: dispatch is this step's decision, made
from `AUTHOR` + `ME_ENGAGED` + `HEAD_CHANGED`.

**`HEAD_CHANGED` compares SHAs, not dates**, and that is the whole reason it exists.
`committedDate` is the commit's own date rather than the push time, so an author who wrote a
commit before your review and pushed it after leaves every date older than your review while
the code did change — a timestamp check reports nothing new and the reply-confirmation never
runs. Each review record carries the `commit_id` it was written against; comparing that to the
current head answers it outright.

1. **Reply-confirmation (Case 2b)?** — pick 2b when EITHER holds:
   - the user says "作者回覆了幫我看" / "確認作者有沒有處理到", or
   - the probe shows `ME` already appears in this PR's reviews/comments **and** the author later replied or pushed commits (confirm via the timeline).

   Do not skip this because the user only pasted a URL — a fresh session has no memory of your earlier review; the "I already commented" signal must be probed, never assumed absent.
2. **Else determine ownership** (primary = `author`, the definitive "whose PR" signal):
   - No PR exists (pure local branch, reviewing `base..HEAD`) → **Case 1** (pre-PR self-review)
   - `AUTHOR == ME` → **Case 1** (my own PR)
   - `AUTHOR != ME` → **Case 2a** (someone else's PR, first review)
   - **Fallback** — when `author` can't resolve ownership (bot / automation / CI-opened PR): check `gh pr view --json assignees`. Assignees include me → Case 1; else → Case 2a.

## Comprehension first (Case 1 & 2a — before any critique)

Before reading the changed code or raising findings, state in 1–3 lines: **what problem does this change solve, and what is the solution approach?** Source it from the PR description / commit messages / linked issue. (The format-change before→after and the layer-handoff walked case below sit outside this limit.)

**另外找出這個改動歸哪一份產品規格管,寫出規格的 `檔案:行` 與整份規格的 GitHub 連結(`https://github.com/ardge-labs/ardge-project-issues/blob/main/<路徑>`,路徑中的空白寫成 `%20`),或寫「查過需求 repo,沒有對應規格」。** PR 描述與 linked issue 講的是作者要解什麼,規格講的是產品答應了什麼,兩者不同,而 finding 的定調常掛在後者:linked issue 一句「使用者能修改既有 bond」可以讀成成員編輯,而規格上只有綁定與整個解除兩個操作,同一組改動最大的一則 finding 因此從「補一道檢查」變成「這條路該不該存在」。判準是這個改動有沒有使用者看得到的操作,有就一定有規格。本 workspace 的需求 repo 是 `ardge-project-issues/`,分 `system-application/<app>/` 與 `system-mechanism/`;引用它的 finding 依第 7 關的第三類來源處理。

This is the foundation for design critique — you cannot judge whether the solution targets the root cause (根因對齊) without first understanding the problem. It also keeps you and the user on the same understanding of the change before diving into the diff.

**Facts from the description; build the causal chain yourself.** The author already holds the domain model, so a PR description can open on mechanism — an internal key name, a flag name, an upstream package's function name, or a mechanism it simply assumes you know exists. 理解 cannot: reuse that opening and the reader stalls on the first sentence, and every finding after it inherits the same gap.

替換規則:`理解` 的**第一句不准**出現上游 / 內部的名詞(元件名、key 名、旗標名),**也不准預設讀者已經知道某個機制存在** —— 讀者缺的往往是前提,不是名詞,所以只擋名詞的版本會放過「名詞乾淨但仍然從機制講起」的寫法。先把因果鏈寫完 —— 壞的是什麼、為什麼會惡化、為什麼原有機制沒攔住 —— 機制名詞之後才出現,且只在支撐這條鏈時出現。例:「kube-apiserver 內建 compactor 要開機後 10 分鐘才第一次真的壓縮」違規(`compactor` 是上游元件名,而「壓縮」預設讀者已經知道有東西需要被清掉);「etcd 改一個值不是覆蓋,是再加一筆,舊的那筆要靠清理才會消失」合規,而且走到同一個結論。第一句不靠附子句豁免。之後的句子,寫完逐一列出 `理解` 裡的每個上游 / 框架名稱(middleware、SDK 型別與函式、旗標),回文字裡找它第一次出現的那句有沒有說它在這條流程裡做什麼的子句,找不到就補一行括號;判準與下面 `問題` 欄那條逐詞檢查同一套,只是欄位不同。指稱一整條鏈的集合詞(「gin middleware」「那些函式」)要點名成員,一個一個寫出來。repo-local 與作者自取的詞照 Output model〈Repo-local 詞彙〉那兩段處理。

**Format-change PRs: show a before→after example.** When the change alters a serialized / on-disk format (config schema, proto wire, DB schema, API payload), the 理解 carries a concrete before→after of the *shape* (minimal JSON/struct snippets), not just prose. A data-shape diff makes the change graspable faster than words — where a field moved, whether its meaning changed, which keys disappear.

**Layer-handoff claims: walk one case before and after.** When your own 理解 draft contains a sentence of the shape "A computes / writes X, but B does not see it, sees a stale value, reads it before A writes it, overwrites it, or sees it when it should not" — in a 中文 draft the literal signals are `看不到`、`讀不到`、`拿不到`、`讀到舊的`、`沒傳到`、`沒帶過去`、`被蓋掉`、`順序不同` — follow the 1–3 lines with one concrete case walked twice — before the change and after — one line per step, listing only the values that change at that step (what the consumer reads, plus the final outcome). Write it as a fenced ```text block; the diagram term check in 〈Repo-local 詞彙〉 applies to it. It lives in the internal report only; the posted recap stays one to two sentences, since the author already holds the flow.

---

## Case 1: my own code / my PR (self-review)

Your own code, so **both** correctness and cleanup apply, and cleanup may be auto-fixed.

1. **Comprehension** (above).
2. **Design critique** of your own approach — apply the *Design critique* section below; does your own problem statement and solution hold up?
3. **Delegate correctness/security** → `x-code-review` (operates on `base..HEAD`; cross-repo mode auto-detected — when it fires, map its Defects / Design Trade-offs / Needs Clarification buckets per the table under Case 2a below, not the CONFIRMED / PLAUSIBLE pair).
4. **Delegate cleanup** → `x-code-improvement` (reuse / altitude / quality / efficiency; runs locally and may apply fixes — appropriate, it's your code).
5. Merge both engines' results + your design-critique findings into the internal report (Output model below).

The *Pre-finding verification gate* below applies (drop low-confidence / pre-existing).

---

## Case 2a: someone else's PR, first review

Full PR review. Read-only; cleanup is surfaced only as a high-bar comment, never via `x-code-improvement` (it edits local files — wrong for someone else's remote PR).

### Mandatory pre-step: establish baseline

Before reviewing anything:
1. Confirm the PR's base branch (`develop` / `main` / other) and `git fetch origin <base> <head>` to ensure both refs are current.

   **`origin/<head>` 解析不出來時,不要重試那個 fetch 形式** —— fork PR、以及任何 branch 已被刪掉的 PR(這個 workspace 用 `--delete-branch` 合併,所以每個 merged PR 都是)都會這樣,`pull/<num>/head` 三種都涵蓋。查法與 fetch 的形式見 `references/baseline.md`。這件事必須在 step 1 定案,不能拖:step 2 每一次讀都在 `<head>` 上,一個解析不出來的 `<head>` 會把整個 baseline 一起帶走。
2. Read all files modified in the PR **from the base branch version** to establish a comparison baseline.
   **Always read at a ref — `git show <ref>:<path>`, never the `Read` tool and never a
   working-tree `grep`.** Both read the files on disk, which are whatever branch the clone
   happens to be checked out on — routinely not this PR's head — so the content comes back
   silently outdated and any finding built on it is wrong. `grep` needs naming alongside
   `Read` because it is the reflex for locating a symbol, not for reading a file; its
   ref-reading form is `git grep <pattern> <ref>`.
   Pick `<ref>` per side:
   - **Base**: always `origin/<base>` (base is authoritative on the remote).
   - **Head**: if a local branch matching `<head>` exists, use `<head>`; otherwise `origin/<head>`.
     Prefer local over PR remote on the head side: when the user has amended locally and not
     yet pushed, the local ref is the source of truth and the PR remote is stale.

   **The diff bounds the baseline, not the ref-reading rule.** Which files to compare against
   base is a diff-scoped question; *how* to read any file is not. Findings routinely cite files
   the PR never touched — the caller it breaks, the config still carrying the old value, the log
   line that leaks what the PR set out to protect — and every one of those `file:line` citations
   has to come from a ref too. A working-tree `grep` on a non-diff file returns the line number
   from whatever branch the clone sits on, and a rule scoped to "files modified in the PR" never
   reaches it.

   **The repo has no local clone at all?** Reading at a ref assumes one exists — `git show`
   has nothing to run against. Clone it (one of the two writes named at the top), announce
   that you did, and then apply the ref-reading rule and the base/head ref choice unchanged.

   **clone 之前讀 `references/baseline.md`** —— 那裡有該用的旗標與四個會靜默壞掉的地方:workspace 路徑怎麼推導(推錯會 clone 進單 repo 的 task 目錄,把之後每次 `x-code-review` 翻成 cross-repo 模式)、為什麼不能 `--depth 1`、clone 之後每次呼叫都要帶 `git -C`、以及 clone 失敗時退到 `gh api contents` 的代價——**那一趟上乾淨的判定不存在**。逐檔用 `gh api contents?ref=<sha>` 讀整個 PR 正是這條規則要防的東西:覆蓋率塌縮成剛好打開過的那些,而那就是「用五分之一的 diff 發出乾淨判定」背後的機制。

### Calibrate review depth to PR size

Calibrate on the **hand-written** change size — generated and lock files are excluded from
the count, so `buf generate`'s output volume does not decide how closely a person reads:

```bash
~/.claude/skills/x-pr-review/scripts/pr-size.sh --repo <path> --range <base>...<head>
```

It prints `hand-written: N lines / M files` and the excluded list with a reason per file, and
takes the same ref pair you are reading at rather than GitHub's totals. Compare the
hand-written figure against the tiers below — the script deliberately does not name the tier,
so this section stays the only place the boundaries live.

**This is not the PR's own `additions + deletions`,** which counts generator output. Measured
on one real PR: 543 raw against 166 hand-written — the large tier versus the middle one, and the tier gates
three separate decisions (depth here, whether `x-code-review` is delegated, whether the
refutation subagent spawns). Hand-writing the sum is also where it goes wrong quietly: the
same PR was hand-totalled as 165.

Evaluate in order, **first match wins** — the second tier's `otherwise` is only meaningful
against the first one having already been tested.

- **small tier — < 50 lines AND ≤ 3 files** — single-purpose fix or value tweak. Acceptable output: 0 findings (say so plainly), or 1 narrow `issue (blocking)` if there's a real bug. Do NOT delegate to `x-code-review` unless the diff includes non-trivial new logic.
- **≤ 300 lines otherwise** — normal scope. Design critique + correctness delegation both appropriate.
- **> 300 lines** — large change. Full pipeline; consider splitting feedback by file.

The second tier reads `otherwise` rather than a `50–300` band because the first one is an AND
of two conditions: a 30-line diff spread over 8 files fails it on the file count while sitting
below 50 lines, and a numeric band starting at 50 leaves that PR in no tier at all. Measured
on api#864 — 30 hand-written lines, 8 files. Every site that acts on the tier cites this list
rather than restating the numbers, so a gap here leaves all of them undefined at once rather
than making any one of them disagree.

A small PR getting 1 blocking finding + multiple medium findings is a calibration failure, not thoroughness. The reviewer's job is signal, not volume — if the body of a finding doesn't justify "this must change before merge" or "this is a narrow nitpick", drop it.

### High-risk change classes (calibration override)

When the PR touches any of these, do **not** calibrate review depth purely by line count — even a **small-tier** diff warrants full design critique:

- **Cluster microservices** — failures hit production immediately; potential outage or data corruption
- **Go packages / shared libraries** — bugs cascade to every downstream importer
- **Public API contract changes** — external callers can't be force-updated; breakage is permanent
- **DB schema / migrations** — irreversible on production data; rollback cost is extreme

Surface affected callers/consumers and call out backward-compatibility concerns explicitly.

### Then: comprehension → design critique → correctness → cleanup

- **Comprehension** + **Design critique** + **race classification** — apply the shared sections below.
- **Correctness/security** → **delegate to `x-code-review` whenever this repo has a local clone. The PR head does not need to be checked out.** Invoke it in this session with `Skill(x-code-review)` — do not wrap it in an `Agent`. Its Step 2 builds the review subagent (sonnet) with the prompt contract that the gates below are placed into; a wrapping agent becomes that subagent itself and skips the contract — on PR 249 it ran on the session model, skipped the `x-coding-standards` filter, and its disclosures never reached this report. **Launch it as soon as you can write its scrutiny list, not after your own review is done** — the pass is the longest step (14 min on a ~6000-line PR) and runs in the background while you do design critique. The **scrutiny list** is a required field of the delegation prompt, labelled "not conclusions — verify yourself": the mechanisms your first read of the diff flagged as risky (shared state between writers, write-before-validate ordering, credentials crossing hosts …). It is what makes early launch cost nothing — on manager PR 846, three of the areas it named became findings (two blocking, one follow-up) — so launching before you can write it (right after the fetch) trades that for a couple of minutes. What waits for your review to finish is the refutation subagent, which needs your candidates. After the baseline step's `git fetch`, the ref pair it needs already exists; hand it over as its documented `A..B` range parameter and it runs in explicit-range mode: it takes the range verbatim instead of deriving one from your local `HEAD`, reports a dirty working tree instead of stopping on it, and reports without offering auto-fix (correct for someone else's code). Four things to get right when composing the invocation:

- **Pick the head side exactly as the baseline rule picks it** — `<head>` when a local branch of that name exists, `origin/<head>` otherwise. Hardcoding `origin/<head>` would point the deep correctness pass at the remote while your own source reads used the local ref, so the two halves of one review would examine different code and the deeper half would be the stale one.
- **Three dots**, not two: two compares endpoints and turns base-side commits into inverted diffs.
- **Name the repo with `--repo <path>` whenever cwd is not that repo.** Its mode detection reads cwd, so from a directory holding several repos a range now comes back as `VERDICT: error` (exit 1) listing the candidate repos — `--repo` is the only thing that resolves it, and neither the branch name nor the refs can supply it (`origin/develop` resolves in every repo here).
- **A fork PR's head is not a branch on the base remote**, so `origin/<head>` will not resolve. Fetch it into a local ref first — `git fetch origin pull/<num>/head:pr-<num>` — and pass `pr-<num>` as the right side.

For a **re-review round** (you reviewed this PR before and the author has pushed since), pass your last-reviewed commit as the left side instead of the base — the full range would re-review everything you already cleared. The only state with no premise to run on is **no local clone of this repo at all**, and the baseline step above resolves that by cloning — so "remote PR" on its own is never the reason to skip delegation. Skipping it means the deep correctness pass never runs and the review degrades to whatever the diff reading happened to notice. Subject to the size gate above: do not delegate for the **small tier** unless the diff has non-trivial new logic. The Pre-finding verification gate **also applies to delegated findings** — the subagent does not inherit this skill's rules; include the eight checks in the delegation prompt explicitly, **after** that skill's own FIND/VERIFY/sweep instructions and labelled as additional gates on the survivors. They filter what VERIFY already kept; putting them earlier reads as a competing verdict scheme and the subagent has to guess which one governs. **Pass the eight checks only — not the tier classification that follows them**: the subagent's verdicts stay CONFIRMED / PLAUSIBLE and you map them to tiers here, so carrying the tiers along gives it two competing schemes. Translate what the subagent cannot see: check 1's "baseline rule" is the explicit-range read commands `x-code-review` already passes; `證據` and `問題` are the finding's failure-scenario and description fields (its output format has no `證據` field, so a literal reading drops every finding); check 6's dedup against the Output model stays here. **Neither check 7's skill-file arm nor its spec-repo arm travels** — that pass produces a defect report, so its only rule source is the project's own documents; pass check 7 as the project-document source alone (the gate's own division of labour, which is cut by 產物, says why). `x-code-review` returns findings tagged CONFIRMED / PLAUSIBLE — a PLAUSIBLE finding carries a concrete failure scenario, so map it to your **Follow-up** tier, not Drop.

  In **cross-repo mode** (auto-detected when the working directory holds more than one repo) it returns a different vocabulary — **Defects / Design Trade-offs / Needs Clarification** — so map those three instead:

  | it returns | your tier |
  |---|---|
  | **Defects** | blocking-tier — a named triggering sequence with a wrong outcome |
  | **Needs Clarification** | **Follow-up, never Drop.** Same shape as PLAUSIBLE: a real mechanism whose trigger could not be confirmed from code alone, which is precisely what the author must answer. Dropping it discards the one thing that skill refuses to drop silently |
  | **Design Trade-offs** | not a finding. Name it in the 理解 section only when it bears on the verdict; otherwise omit it — do not open a section for it |
- **Cleanup (optional, comment-only)**: if you spot a genuinely valuable cleanup (reuse/quality/efficiency — root-cause altitude belongs to 根因對齊 under Design critique, not here) that passes the verification gate, raise it as a single high-bar comment ("請作者考慮…"). Do **not** run `x-code-improvement` (it edits local files — wrong for a remote PR) and do **not** flood nits.

---

## Case 2b: reply confirmation

Triggered by: "同事回覆了幫我看", "幫我 review 他的回覆", PR URL + reply review instructions.

### Execution order (mandatory)

1. **Read the reviewer's original comments** — understand what each comment requires
2. **Read the author's responses** — check if they correctly understood each original comment
3. **Look at the corresponding commits/diff** — verify the code matches the stated responses

Use the original comments as the verification framework; commits are supporting evidence, not the starting point.

### Verification criteria

For each comment → response pair, evaluate:

- **理解**: Did the author correctly understand the reviewer's core concern?
- **完整性**: Were all raised points addressed, or only some?
- **品質**: Is the solution design sound, or just the minimum change to close the comment?
- **一致性**: Were related tests, docs, and other call sites updated in sync?
- **機制主張**: 回覆是「有 X 所以不會發生」這類說法時，trace 到 code 得出結論（引上游原始碼時標版本）；結論要靠執行期狀態才會觸發，就寫出驗證方式、建議使用者實跑；結果連同做法帶回給作者。

### Warning signs

- Using comments to rationalize a flawed design rather than fixing it
- Renaming on the surface without resolving the structural issue
- Agreeing in words but diverging in implementation
- Describing a scenario that wouldn't occur in the current architecture to justify a design decision

When reply confirmation also needs code-quality review, combine both into a single agent prompt to avoid reading the same diff/source twice.

---

## Shared: Pre-finding verification gate (Case 1 & 2a)

Before raising any finding (design critique or correctness), each candidate must pass ALL eight checks. If any fails, **drop the finding** — do not downgrade to nitpick to keep it alive. Downgrading-instead-of-dropping is how manufactured findings leak through.

1. **Source code read?** Have you read the actual source file at the relevant line range (via `git show <ref>:<path>` per the baseline rule), or only the diff snippet from `gh pr view`? Diff hides surrounding context (function signatures, sibling fields, callers). A finding built on diff alone is too shallow — re-read source before raising.
2. **Already addressed in PR description — 那句話是理由,還是主張?** Quote the PR description verbatim, then apply one test: **這句話能不能靠讀 code 或探測狀態推翻?**
   - **不可否證(設計取捨的理由)** → drop。例:「選 `fqdn-uri` 因為 host 要跨 namespace 解析」。作者已經給了 why,不要叫他重講。
   - **可否證(事實主張)** → 去查,不要當成已被 addressed。例:「CNPG only applies `bootstrap.initdb` on first init」。查出為真才 drop;查出為假,那是最高等級的 finding——錯的前提會讓後續維護者照它做合併順序與部署決策,傷害大於單純漏抓一個 bug。
   把兩者收在一句「作者已經提到了」會 drop 掉最強的那一類:描述裡**談過**某個情境,不等於**談對了**。
3. **PR-introduced or pre-existing?** Is this behavior introduced by THIS change, or pre-existing/documented as intentional in proto doc, source comments, or sibling code? Confirm via `git show origin/<base>:<path>`. Pre-existing intentional behavior is out of scope — note as "既有狀態" but do not raise as a finding the author must address.
4. **Asking for redundant documentation?** Is the finding really "the author should write release notes / CHANGELOG / behavior change notice"? Authors are responsible for those by convention — flagging it adds nothing. Drop.
5. **後果落在誰身上,證據到手了嗎?**（只適用宣稱有行為後果的 finding——`issue` 兩級與 `question`;`nitpick` / `note` 這種本來就不宣稱後果的,跳過這關。）寫得出 `問題` 那句要指名的**承受後果的具體對象**嗎（一支執行檔、一台裝置、一個 caller、一條 CI job）?那個對象若不在這次 review 的 PR 裡,`證據` 就必須帶上它所在 repo 的 `file:line`——**沒有那個 `file:line` 就先去讀那個 repo,不要先寫 finding**。本機通常已有 clone,成本是一次 `git cat-file`。
   只給本 PR 的程式碼路徑時,跨 repo 的 finding 會被讀成本地的旗標 / 分支問題,而不是下游會壞掉,作者也無從判斷嚴重度。

   **宣稱既有安裝 / 升級 / 某條部署路徑會壞的 finding,`證據` 要再多帶一條引用,而且來源不得是這組 PR 的任何一份**——GitOps 的 reconcile 組態、OTA 流程定義,或實機的唯讀狀態讀數。這是必填欄位而不是提醒:欄位空的就不成案,不需要先察覺「這裡該小心」。理由是這類 finding 的嚴重度不掛在改動本身,而掛在「這個改動會不會送到那些機器上」,而那個答案在 PR 裡永遠找不到——作者只要回一句「那條路徑不會套用」,整則就倒,連帶讓同一輪其他 finding 都變得可疑。實機證據通常一次唯讀查詢就拿到(`kubectl get` / `flux get` / 讀組態檔),不動任何狀態。

6. **這則 finding 要求作者做什麼?** 用一句話寫出那個動作;寫不出來 → 丟掉。
   前五關問的是**是不是真的**,這一關問的是**要求了什麼**——除了「修法在觸發條件下可不可行」這一項會在第 8 關被回頭覆核(觸發條件要到那一關才在手),兩邊其餘互相獨立,所以一則每句都成立的觀察可以五關全過、卻仍然該丟:它讀起來像 finding,但作者拿到不知道要改什麼,方向甚至可能是**減輕**的。這關最便宜,候選一浮現就先答它,省下對注定要丟的項做前五關的成本。寫出來的那句動作要留著——組裝報告時拿它去重(見 Output model)。跨則去重不在這裡做:第一個候選當下還沒有「另一則」可比。

7. **這則 finding 引用的規矩,寫在哪個檔案的哪一行?**(只適用引用了規矩的 finding;純粹描述行為後果的跳過這關。)寫出那個 `file:line`;寫不出來 → 丟掉。
   合法的來源有三個,前兩個是:**被 review 的專案自己的文件**(`CLAUDE.md`、`CONTRIBUTING.md`、PR template、`docs/` 下寫成規範句的),以及**這套 review 工具鏈自己的 skill 檔**;第三個是需求 / 規格 repo,單獨寫在本關最後一段。只住在 `~/.claude/rules/` 或 memory 裡的不算——那些規範的是**你怎麼工作**,不是這份 code 該長什麼樣,作者既無從查證也無從遵守。
   引到的那一行要是**針對某個具體產出的規範句**(標題長度、label 有沒有、檔案該放哪),不是需要解讀的原則(SOLID、「偏好組合而非繼承」)。原則沒有可比對的物件,套到別人的改動上只會產出「我覺得這樣比較好」。
   **來源是 skill 檔而非專案文件時,嚴重度上限是 `nitpick`**;而唯一依據是 skill 檔的 PR metadata 項(標題、label、描述格式)歸合併前閘門的報告,那份從不對外貼。專案自己的文件沒說的事,不值得佔用作者一則 comment——但仍然要在給使用者的報告裡寫出來,由使用者決定要不要轉告。(以專案文件為依據、或不引任何規矩的 PR 描述觀察不受這條限制,照 `note` 處理。)
   這幾個來源的分工是按**產物**切的,不是按規矩內容切:correctness / security 那條委派出去的 pass **只認專案自己的文件**,skill 檔與規格 repo 都不隨它出去,因為它產的是缺陷報告,標題長度與產品範圍都不在它的職責內;合併前閘門認它自己的 checklist,因為那份報告從不對外;這一關管的是要貼給作者看的 finding,所以三個來源全收、但 skill 檔那個帶上限。這三個**消費流程**各自一致,不要拿其中一處的說法去推翻另一處(它與上面三個**來源**是兩件事,別把兩個「三」讀成同一組)。
   **第三類來源:本 workspace 的需求 / 規格 repo**(如 `ardge-project-issues/`),用在回答「這個操作是不是產品答應過的功能」而不是風格命名時。它與前兩類受同一條判準檢驗——作者查得到、也遵守得了,產品範圍本來就歸他管——所以**與「專案自己的文件」同級,不吃 skill 檔那半的 `nitpick` 上限**。歸錯類的後果是實際發生過的:一則「這條路該不該存在」的範圍問題若被壓成 nitpick,作者會照 nitpick 處理,而它要問的是整段 API 表面的存廢。仍然不算的還是只住在 `~/.claude/rules/` 或 memory 裡的東西,理由不變。

8. **這則 finding 要什麼條件才會發生?**(只適用宣稱有行為後果的 finding——`issue` 兩級與 `question`;`nitpick` / `note` 跳過。)把觸發條件寫進 `證據`,附可查證的 `file:line` 或量化依據;寫不出來 → 丟掉。
   「這段程式碼被執行時」這種恆真條件不算——要寫得出**什麼要先出錯或先成立**,例如「`os.ReadFile` 以 ENOENT 以外的錯誤失敗時」「apply 在寫入階段失敗**而且**該次 rollback 的刪除也失敗時」。這一關擋的不是罕見,是**沒查過**:定級與修法都掛在這個答案上,而它在讀 code 時就查得到,等對方問「這機率高嗎」才去查,前面整輪的定級都是空的。
   **拿它回頭檢驗修法**:提出的修法必須在同一個觸發條件下仍然可行。實例——觸發是紀錄檔讀不到,而修法「把檔案改名擱置」需要同一個目錄可寫,在該條件下不成立,所以那不是修法,這則不成案。
   **觸發落在產品外(檔案系統故障、硬體、斷電)不是丟掉的理由**,這一關只問有沒有查過並留下證據;後果的輕重在 `定級理由` 逐則判斷。
   race / concurrency finding 分兩種,不要用同一句帶過。**Class A 常駐 race 是恆真觸發的唯一豁免**:它的觸發本來就是「這段程式碼被執行時」,把它分類成 Class A 這個動作本身就是這一關的答案,不必再查機率(分類判準見下面 *Race / concurrency findings*)。**Class B 窗口 race 不豁免**:它的觸發條件展開成 AND-gate,那是**呈現形式**,每一條 gate 仍然要查證並留下證據。

**兩類 finding 各有一個必填欄位。** 這兩類的每一句都可以成立而結論是錯的,所以欄位空著就不成案——是欄位,不是提醒。

- **宣稱一句文件 / 註解 / schema 說明寫錯**(這裡指的是**產物裡**的句子——程式碼註解、schema / swagger 說明、proto doc;PR 描述裡的句子走第 2 關的可否證性測試,同一句同時是兩者時兩關都要過):先寫出「它在哪個讀法下是對的」,再寫為什麼那個讀法不成立。寫不出前半段,表示還沒讀懂那句話在自己的框架裡指什麼。實例:某個 HTTP 欄位的說明寫「a permission domain with no desktop app (e.g. apps, cloud)」,而 `apps` 正是那個 app 的路由在檢查的權限——看起來是事實錯誤。但在那句話自己的框架下(「desktop app」指的是這份清單裡的項目),`apps` 確實不 gate 清單裡任何一項,所以那句是對的,這則不成案。
- **宣稱程式裡兩處不一致**:指名**哪一邊是對的**。說不出來就不要提——作者收到「這兩處不一致,建議統一」會自己挑一邊,而挑錯的那半正是你剛剛沒攔下來的。實例:同一個回應型別上,既有的 `permissions` 沒有 `omitempty`(空值序列化成 `null`)、這次新加的 `shortcuts` 有(空值整個 key 消失)。不一致是真的,但兩邊都不對:`x-coding-standards` 規定 response 欄位不加 `omitempty`、空的 slice 序列化成 `[]`,所以對的是第三種寫法——`shortcuts` 拿掉 `omitempty`,兩個欄位都初始化成空 slice。往任一邊「統一」都是錯的;沒指名時提出去,作者會挑其中一邊。

After all eight pass, classify into one of **three** tiers (a binary High/drop bar silently loses genuinely useful non-blocking items and buries real ops risks):

- **In report (blocking-tier)** — direct evidence, behavior outcome concrete and falsifiable. Label `issue (blocking)` / `nitpick` (Conventional Comments). `blocking` = 必改才能 merge(bug、新行為完全沒測試、文件宣稱的保證在程式碼裡不成立;只錯在措辭或失敗形狀的,照 `references/refutation.md` 定 `nitpick`)。`nitpick` 的定義很窄:typo、違反專案明文約定的命名、違反本工具鏈 skill 檔明文約定的命名 / 格式(見 gate 第 7 關的來源與上限)、與**緊鄰程式碼**不一致的風格、有客觀正解的小改——「我覺得這樣讀起來比較好」不算。
- **Follow-up (non-blocking, in report under `Follow-up`)** — NOT merge-blocking, but names a **concrete failure mode or ops/operability risk**: silent no-op on a future API/version bump, a wedged state that won't surface without an event/metric, a guard that only bites under a specific future condition, a real maintainability hazard with teeth. **The test: you can state the concrete scenario it prevents** — 讀第 8 關已經寫進 `證據` 的那個觸發條件,只問它有沒有點名一個情境,不在這裡重新推導一個。This tier exists so useful non-blocking items aren't lost to the high bar — it is NOT a home for style.
- **Drop** — style / naming / structure preference, bikeshedding (wording, ordering, phrasing), defensive improvement or "could add a test" with **no named failure mode or invariant**, pure speculation. **Do not include at all** — no "for your consideration" / "待確認".

Boundary between Follow-up and Drop is the test above: if you can name the concrete scenario it prevents → Follow-up; if the justification is "reads better / cleaner / more robust in general" → drop.

**分界只有這一條,不要再疊「感覺最弱」的主觀篩子**(那會把三層打回 binary,正是它要避免的)。定級在提出當下就定死:放進報告後又在對話裡改口說「這是最弱的、第一個該砍」,等於當初沒定級——講不出情境就在提出前丟掉,提出後才降級是 hedge 的一種(見 `feedback_no_hedge`)。編號同理,`publish-format.md` 要求 F-id 跨輪 carry forward,給了編號就是承諾走完後續每一輪。

### 交出去之前要過一次獨立反駁

Correctness 委派出去的那半有 FIND 與 VERIFY 分離,理由是判斷一個候選時不該用寫它時的同一套推理。design critique 自產的那半沒有這道分離——同一個 context 既提出主張又核可主張,而核可用的正是提出時的前提。所以**報告交出去之前**,送一個 read-only subagent,任務是**反駁**,不是複核。送兩類東西進去,它們的失效方向相反:一類是我提出來的主張要被推翻,另一類是改動裡**已經被當成真的**句子要被推翻。

- **一、自產的 finding** —— 落在 `issue` 兩級與 `question` 的自產項,它們的**主張**要被推翻。
- **二、這次 diff 改動的散文** —— `.md` 的新增行與程式碼註解的新增行,**逐行枚舉**,不挑「看起來像在講理由的句子」(關鍵字清單補不完,而漏掉的那句同樣是假的);裡頭**已經被當成真的**行為斷言要被推翻。

第二類非送不可,因為**擋它的另外兩道關在這種失效下必然全綠**:下面〈Design critique〉的〈內部一致性〉比的是幾份敘述**互相**一致,而一句錯的理由通常被複製到註解、spec、tasks 好幾處、處處一致;委派出去的 correctness pass 對註解的定位是**判準**(`x-code-review/SKILL.md` 的 Code-comment compliance 準則,找的是 code 違反註解)與**降級依據**(同檔 cross-repo VERIFY 的 Intentional by design 與 PLAUSIBLE by default 兩條,引到註解就把候選 demote 成 design trade-off),兩個方向都以註解為真。所以一句寫錯的理由不但抓不到,還會讓引到它的 finding 一起消失。

**spawn 之前讀 `references/refutation.md`**——兩類各要餵什麼、掃描用的兩條指令、verdict 三支、REFUTED 要回的 grep pattern 與副本清單、實跑的環境條件、兩類對「無法判定」相反的處置,都在那裡。憑印象組 prompt 會漏掉「可以離開 repo 實跑」與「判 REFUTED 前先寫出這句在哪個讀法下是對的」這兩條,而它們正是這一步的效力與假陽性防線所在。

`nitpick` / `note` 不送——它們本來就不宣稱行為後果,沒有主張可以攻擊。**落在 small tier 的 diff 免送第一類**,與上面 correctness 委派用的是同一條校準:小又已驗證的改動不值得為它自產的 finding spawn 一個 subagent。

**整步跳過的條件是兩類都空**,不是其中一類空。第二類不吃 small tier 那條豁免:三行的 diff 一樣寫得下一句錯理由,而它的代價——下一個維護者照它決定修法與合併順序——不隨 diff 變小。兩類共用同一個 subagent,所以第一類被豁免、第二類非空時仍然只 spawn 一次。

**跑過的痕跡不靠記得。** 第一類寫進每則 `issue` / `question` 的 atom 多出來的那行 `反駁:`;第二類寫進 ledger 那行的計數,`散文行 31 行 / 行為斷言 7 句:2 REFUTED、1 無法判定、4 CONFIRMED(3 則的引用落在 diff 外)`。兩者都是在寫報告的當下就看得見有沒有跑過,不必先想起有這個步驟——第二類尤其需要,因為 CONFIRMED 的句子不產生 atom,而那是多數,沒有計數時「掃過 0 句」與「這步沒跑」長得一模一樣。

**最後那個括號是「有沒有真的離開 diff」唯一的對照物件,所以 CONFIRMED 也要附證它的 `file:line` 或指令輸出。** 一個從沒離開 diff 的 subagent 回的 CONFIRMED 與一個實跑過才回的 CONFIRMED,產物本來一模一樣:兩者都不變成 finding,都只讓計數加一。而「留在 diff 裡就判不出來」正是這一步要解的那個失效——那句錯理由當初就是要離開 repo、跑一次上游工具才推翻得掉的。引用位置一數出來,停在 diff 裡的那趟就會顯示成 `0 則落在 diff 外`。跳過整步時在同一行寫明理由;兩欄的完整寫法見 `references/refutation.md`。

An empty **blocking** section is a valid outcome — do not manufacture `issue (blocking)` / `nitpick` to fill it. But still surface any qualifying Follow-up items (a clean blocking section + 2 real ops-risk Follow-ups is a normal, healthy report — not a "thin" one). And a clean verdict needs the same source-read that check #1 demands — recorded as a **coverage list you derive from the file list, never from memory**:

```bash
~/.claude/skills/x-pr-review/scripts/pr-files.sh <owner>/<repo> <num>
```

It emits one row per changed file — `status`, the ref that path is readable at, the path, and
a `→ disposition:___` placeholder for you to fill — then cross-checks the row count against
`changedFiles` and closes with a `VERDICT:` line. **Read that line:**

| `VERDICT:` | meaning |
|---|---|
| `ok` | every path is listed; fill in the dispositions |
| `count-mismatch` | the list is incomplete — **no clean verdict is available**, and do not fill anything in |
| `degraded` | the `/files` API failed and the fallback has no `status` column, so `removed` paths cannot be identified; every `read-at:head` is a guess |
| `unavailable` | the list could not be built at all — **no clean verdict is available**, same rule as a failed clone |
| `error` | the invocation itself was wrong (missing or unknown argument, `--local` not a repo) — fix the command and rerun; nothing was read |

Above 3000 changed files the API itself stops (GitHub caps that endpoint, `--paginate`
included), so the script refuses and asks for the local clone instead:
`pr-files.sh <owner>/<repo> <num> --local <path> --base <ref> --head <ref>`. **Pass the same
two refs the baseline step chose** — `origin/<base>`, and `<head>` when a local branch of that
name exists. Passing `origin/<head>` here while reading source at `<head>` splits the coverage
list from the reads, so the list would account for files the reads never saw.

The count cross-check is the whole point of running a script here rather than a query: on a
301-file PR the obvious command (`gh pr view --json files`) hands back 100 paths with no
indication that it truncated, every one gets a disposition, the gate passes, and the clean
verdict is issued on a third of the diff.

`status` decides which ref a path is readable at — the script fills that column, and these are
the four dispositions you choose between:

| disposition | when | meaning |
|---|---|---|
| `讀過 (head ref)` | `added` / `modified` / `renamed` | read at `<head>` via `git show <head>:<path>` |
| `讀過 (base ref)` | `removed` | the path does not exist at head — `git show <head>:<path>` exits 128. Read the deleted file at `origin/<base>` and account for what its removal takes away |
| `跳過:generated` | any | generated / lock file — name which |
| `跳過:trivial` | any | say why it is trivial (import-only, string constant, fixture rename) |

A `renamed` row carries its former name in the `(was: …)` suffix — the old path is unreadable at head, and it is what callers and docs still reference, so use it when the rename is what the finding would be about.

The list goes **before** the verdict line, and the verdict must be consistent with it: **every path carries exactly one disposition, and "沒看到要改的地方" is unavailable while any path is unlisted, while the count cross-check disagrees, while the script reported `VERDICT: degraded`, or while a `跳過` carries a reason you cannot write down.**

`degraded` has to be named here because it satisfies every other condition — every path listed, the count agreeing, each disposition writable — while the `status` column was never obtained, so each row's `read-at:head` is a guess and a deleted file is indistinguishable from a modified one. A clean verdict off that list is clean off a ref column nothing verified.

機械推導才算數的理由:憑印象寫的清單會用和判定一樣的方式出錯——它是判定自己的產物,不是另一個來源,所以擋不住任何東西。舊寫法「every **substantive** changed file」正是這樣壞的:`substantive` 沒有對照物件時就等於「我讀到的那些」,兩成覆蓋率會被歸類成夠了。逐檔標處置把 substantive 從一個沒人檢查的總量,變成一個一行一行寫出來、作者和使用者都能反駁的判斷。

Declaring clean off the diff is the false-negative mirror of the manufactured-finding failure this gate prevents.

## Shared: Design critique (Case 1 & 2a)

Look beyond code quality — actively examine the design decisions:

- **前提驗證**: Does the problem statement's assumption hold? Backed by real cases, or defensive assumption?
- **根因對齊**: Does the solution target the root cause, or work around it? (e.g., cleaning up at the consumer instead of fixing at the source)
- **背景完整性**: Does the description give reviewers enough context? Can someone unfamiliar with the domain follow the causal chain? 下面兩件由 reviewer 自己補進 `理解`,不等描述提供:
  - 改動新增了一個自動動作(重建、重試、清理、恢復)時,寫一行使用者手動操作的路徑(停止、刪除、各種重開機入口)會不會碰到它,附擋住或放行那條路徑的 `file:line`。
  - 以 `git log -S '<字串>' origin/<base>` 查出讓這個缺口成立的每一個條件(例:讓某種狀態沒有任何分支處理的判斷式、關掉原有保護的設定、決定缺口有多大的常數或閾值)各是哪個 commit 帶進來的,每一個寫出 commit、日期與作者;查不到就寫出用過的字串。
- **內部一致性**: Are the PR description, code comments, and function docstrings consistent with each other?
- **分支對比驗證**: When comparing behavior between two code paths, cite the file:line of each path's data producer — not just the local code inside each branch. Producers are where invariants (sort order, state lifecycle, ctx ownership) get established; branch internals are only consumers. Looking only at branch-internal code yields false symmetry conclusions ("branch A does X, branch B doesn't") when the invariant was actually set upstream.

### Race / concurrency findings: classify before commenting

Race / ordering / concurrency findings split into two classes with different protocols. **Classify first.**

**Class A — 常駐 race**: triggered by ordinary runtime conditions (every RPC, every concurrent goroutine pair, every retry). Examples: unprotected map read/write, missing `sync.Mutex` around shared state, channel send after close, double-close, time-of-check-to-time-of-use on hot path.

→ **Commit to `issue (blocking)` directly.** No trigger / probability analysis needed — the trigger is "the code runs in production." 這是 gate 第 8 關對恆真觸發的唯一豁免,依據就是這個分類本身,所以 `證據` 那一欄寫的是分類理由(哪一段共享狀態、哪兩條執行路徑),不是機率。 Comment body = timeline + minimal fix. Follow the `feedback_no_hedge` discipline.

**Class B — Windowed race**: only triggered inside a bounded window that closes after a one-time event. Examples: startup race before a seeder completes, migration race that dies after first successful run, leader-election handoff window, rolling-upgrade window where old + new versions coexist.

→ **Do NOT commit a verdict in the comment body.** The bug is real (the gate already filtered 假陽性) but the response is a trade-off the author owns. Include:

1. **Trigger 條件 stacking** — every AND-gate that must hold simultaneously: PR-introduced state · runtime window · user action · topology.
2. **實務機率評估** — for each AND-gate, name the deployment / upgrade / ops convention that suppresses or amplifies it (upgrade ordering, maintenance-window convention, call frequency, post-migration permanence).
3. **若踩到的後果** + **修法成本** — e.g. "踩到後 no RPC path can clean the orphan, needs manual kubectl + git rm" / "5 行 + 1 test". Lets the author weight cost vs. consequence.

Close with 2–3 numbered questions (accept + document / fix / "I considered this and the reason it's OK is X"). For Class B, committing a verdict before the author has seen the trade-off wastes a round. **When in doubt, default to Class A** (treating A as B hedges; treating B as A just returns to evidence, which is recoverable).

---

## Output model: internal report (read-only)

When the run finishes, give the user an **internal report** (not posted, no edits) in 繁體中文, using engineering-standard terms (no invented or cross-domain words, e.g. not 病因).

**交報告之前跑一次冷讀**(讀者 = PR 作者)。對象是每則 `issue` / `question` 會貼出去的那段,所以 2a 交報告時要附上貼文草稿(Template B),2b 的報告本來就照 Template C/A 寫(見〈Posting a review〉)。它問的是只拿到這段文字的作者說不說得出要改什麼;主張對不對是〈交出去之前要過一次獨立反駁〉的事。使用者是最後一關:看過、照回饋改完就貼,貼出時不重跑。結果寫進 ledger 那行。spawn 之前讀 `references/cold-read.md`。

**兩份產物的讀者缺的東西不一樣,所以欄位不一樣。** 使用者沒讀過這份 code,得先拿到「這段 code 在要求什麼」才判斷得了 finding 真假;作者就是訂那條要求的人,對他複述只佔篇幅。欄位歸屬:`程式要求` / `定級理由` / `反駁` 內部限定;`證據` 收進貼出版 `建議` 句尾的 `file:line`,以及(僅限觸發條件那一項)折進 `問題` 那句;`根因＋解法` 拆成貼出版的 `問題`(機制與圖)與 `建議`(修法);只有 `問題` 兩邊都在。新增欄位時補進這份對照,不要另立說法。這只管欄位歸屬,不是「凡作者已知就不寫」——Template A 的根因對齊仍然要用 reviewer 自己的話寫出來,approve 的重量建立在那上面(見 `publish-format.md`)。

**Repo-local 詞彙第一次出現要標歸屬。** 只在某個 repo 內部成立的詞——`core`、`carrier` / 載體、`table`、`slot`——在這個 workspace 常常已經被別的東西佔走(`core` 預設是 `arx-platform-core` 這個服務,不是 `arx-go-trust` 的 `internal/trustd/unwrap.Core`)。第一次寫成 `unwrap core`(arx-go-trust 的 `internal/trustd/unwrap.Core`,與 arx-platform-core 無關),之後固定用同一個短稱。**作者在這份 code 裡自己取的名字**是第二類——函式名或註解裡反覆出現、讀完 code 會覺得是普通話、其實只在這份 code 裡成立的詞(`pass`、`projection`、`census`;以該詞在這份 code 裡有沒有專屬意思為準,一般用法的同一個字不算)。候選來源是外顯的:寫進報告的英文詞或它的譯名,也出現在 diff 新增行的識別字或註解裡,就要過這一類。第一次出現時同一句要有一個子句說它**是什麼**(對應哪個函式、一次做哪幾件事),寫不出來就改用普通話;**只在句子裡用到、沒說它是什麼,不算有定義**。判準有兩條:「這個詞在別的 repo 有沒有別的意思」,以及「這個詞是不是只在這份 code 裡才有意思」——兩條都不是「這個詞難不難」。**一行括號、只付一次,不要另開名詞解釋段落**,那會把報告撐散。範圍:兩類都套用在內部報告的每一段(`理解`、跨 PR 的 briefing、每則 finding);貼出版只查第一類與 reviewer 自己新取的詞,作者自取的名字免——讀者是作者,詞是他取的。

**報告裡每一張圖,節點與箭頭標籤上凡屬上面兩類(或上游 / 內部名稱)的詞,圖之前的文字都要有那個說它是什麼的子句。** 普通字(事件、請求、放行)不查。圖上沒有地方附子句,所以那兩類在圖上不會被察覺——檢查方式是把節點與箭頭標籤逐一列出來,回文字裡找;「圖之前的文字」指同一段(`理解` 段本身、或同一則 finding 圖之前的欄位),不能只靠報告更早的段落。找不到的就是缺,用一行括號補在圖之前。照「圖是取代句子不是追加」縮短散文時,這些定義子句要留著。範圍同上一段:貼出版的圖只查第一類與 reviewer 自己新取的詞。實例:「事件 ──投影有變──▶ trigger ──▶ pass」,`pass` 在圖之前出現過(「跑一次 pass」)卻沒說是什麼,`trigger` 完全沒出現——兩者都算缺,讀者只能猜箭頭的終點是什麼;`投影` 有「下面稱『投影』」那個子句,不算缺。

報告第一行是規格出處,獨立一行、不算進〈理解〉:照抄上面 Comprehension first 找到的連結,寫成「此 PR 對應 <規格名> — <連結>」,沒有對應規格就照抄「查過需求 repo,沒有對應規格」。

1. **理解** — the problem this change solves + the solution approach (1–3 lines, matching *Comprehension first*, plus the format before→after / layer-handoff walked case when they apply), then one line of judgment: direction right? mergeable? needs changes?
2. **Findings** — each gate survivor rendered as an atom (below). If nothing survives, say so plainly ("沒看到要改的地方") — never pad a clean verdict or manufacture nits.
   **組裝時去重一次。** 把每則在 gate 第 6 關寫下的那句動作排在一起,**同一個 code 物件上的同一個動作**只留一則——留 `file:line` 指向作者真的會打開的那一處,其餘併進去。判準是**物件**不是動詞:兩個不同檔案的 typo 各自成一則,而「把這幾份 PR 一起合」與「補上那份 values 缺的欄位」是同一則。這一步只能在所有候選都在手之後跑,所以它住在這裡而不是 gate 裡;PR 數量越多越需要,因為同一個落地順序問題可以在每份 PR 上各寫一則、每則都是真的、每則都過關,作者收到的是重複的 comment。

3. **委派出去那一輪的揭露原文轉述**——`x-code-review` 報告 Summary 之後的獨立性那行,以及它自己列出的偏離(沒跑的步驟、以人工代替的過濾),原文放進報告的「沒驗到的」。只轉述 finding 數量,「0 則」會被讀成完整跑完的 0 則。

**Finding atom** — depth scales with severity. Keep `file:line` inline as normal markdown (NOT inside a fenced code block — that kills the clickable jump). Do NOT column-align the labels: CJK label widths break monospace alignment, and bold labels on their own lines read cleanly without it.

- Header on TWO lines (keeps it uncluttered):
  - `<icon> [F<n>] <label> · <category>: <subject>` — subject 一行講原因,短到能當標題、不放識別字,後果留給 `問題`、機制細節留給 `根因＋解法`;順序固定 icon → id → label(與 `publish-format.md` 一致);**id 從內部報告的第一輪就編**,對話裡指名靠它(👍 clean verdict 例外,沒有 finding 可 carry forward,不帶 id)。icon + label per the **full** icon↔label map under *Posting a review* below; all seven are available here, not just the `issue` levels — `question` / `suggestion` / `note` are gate survivors too (per the *Pre-finding verification gate* tiers), and 👍 clean for a no-finding verdict. Category: correctness | security | performance | maintainability | docs
  - `` `file:line` — `symbol` ``
- **程式要求**: 這段 code 正在對呼叫方施加的那條約束——一到三句,用領域詞,**不出現任何識別字**。**REQUIRED 的條件是這則 finding 本身在講一條約束**——缺席、套錯、或寫錯;純粹的實作缺陷(nil-deref、常數錯、漏 error wrap)沒有約束可寫,這一行就不出現,與 `nitpick` / `note` 同。硬填會生出一句為真、成形、卻與主張無關的約束,比沒有更糟。有這一行時貼出去整段拿掉(見本節開頭的欄位歸屬)。**「准」的形狀要跟禁止的那半一起寫**:只寫禁止,讀者會用「一律禁止」的模型讀,而指出誤擋的 finding 在那個模型下不成立。範圍收在**整條約束缺席**——名詞層的缺口由上面〈Repo-local 詞彙〉那兩段與下面 `問題` 那條逐詞檢查管,兩者不重疊:這一欄補的正是「`問題` 句子裡沒有任何詞彙可以觸發那道檢查」的情形。實例:某則 finding 寫「這個形狀本來就是放行的」,而「有一個放行的形狀」從沒出現過,連問三輪才補回來;該寫的是「把網卡綁進 bond,它自己的位址會消失,原本走它的預設路由會搬到 bond 上。所以這裡有一條要求:成員持有預設路由時,只有在同一個請求裡同時講明 bond 的新位址與 gateway,才准建立。」
  **同一份報告裡同一條要求只在最早那則寫完整**,後面的 atom 寫 `程式要求同 F<n>`。範圍是報告不是 PR——跨 repo 報告分 PR 排版,寫完整的那則可能落在別的 PR 段落裡,所以一定帶號;只寫「同上」不帶號的,下一段就對不回去,是看得出來的錯。**寫完整的那則被反駁掉而從報告消失時,把全文升到最早那個還在的引用者身上**——反駁掉的項不進報告、號又空著不回收,`程式要求同 F<n>` 於是指向一個報告裡不存在的號。四份 PR 六則 finding 有三則靠同一條規矩時,複述三次正是把報告撐到讀者吸收不了的那個動作。
- **問題**: **什麼壞了、誰承受、什麼條件下會發生**,一句話。第三項是第 8 關已經查過並寫進
  `證據` 的那一個,這裡只是把它放進句子,不在這裡重新判斷。race / concurrency finding 例外:
  它的觸發條件依上面 Class A/B 的格式展開,不壓進這一句。
  **講到使用者看得到的狀態**(`被判成`、`顯示`、`看到`、`要等…才`、`直到…才變回來` 這類)時,同一句帶上應有的狀態 Y(照 PR 意圖或規格;不確定就寫成問句)與 gate 第 3 關的歸因;PR 之前的狀態可以另寫(通常放時間軸的 PR 前一欄),但不能代替應有的 Y。狀態會隨時間變,就接一張看得到的狀態的前後時間軸(走法同 *Layer-handoff claims*),code 分支樹留在 `根因＋解法`。
  **不要用程式碼路徑或旗標分支開頭**——「`X` 只在 A 分支被讀到」「這兩個 flag 併用會被擋」是機制,屬於 `根因＋解法`;`問題` 要讓沒讀過這段 code 的人自己判斷得出嚴重度。機制開頭的 finding 會被讀成「選項衝突」這種無關痛癢的事,然後多花一輪解釋。
  **也不准預設讀者已經知道那個機制存在**——與 `理解` 同一條(上面 *Comprehension first*),finding 不豁免。有沒有做到由交報告前的冷讀檢查(見〈Output model〉開頭):`問題` 那句出現的每個上游 / 內部詞彙(旗標名、上游工具的設定名、schema 欄位名,以及在這個情境有兩種所指的普通字——`description` 可能是 PR 的也可能是 schema 欄位的),冷讀者說不出它決定什麼,就重寫。反例:「`honorLabels: true` 預設開著,但旁邊寫的理由不成立」(`honorLabels` 決定什麼沒說,讀者停在第一個詞)。正例:「撞名時要留 metric 自己的值還是 Prometheus 貼上的值——這個選擇預設選了 metric 那邊,而寫在旁邊的理由不成立,下一個要動它的人沒有依據可判斷」(先講這個選擇在決定什麼,再講誰承受)。
- **根因＋解法**: cause and fix woven into ONE compact passage — 2–3 sentences, not a wall of text; enough that the reader opens the code holding both the why and the patch. (blocking findings / judgment calls)
- **證據**: the facts you read — quoted line / value / sibling fact, each with `file:line`. REQUIRED for every blocking finding and every judgment call.
- **定級理由**: the single fact that flips the severity. (judgment calls only) 觸發落在產品外(檔案系統故障、硬體、斷電)**不是自動降級的理由**——後果的輕重逐則判斷,斷電把資料檔寫成 0 bytes 導致永久 crashloop 那類就是產品外觸發、後果嚴重。觸發條件本身住在 `證據`(第 8 關),這一欄只寫它為什麼把嚴重度推到這一級。
- **反駁**: 獨立反駁者的 verdict 與依據。REQUIRED for every `issue` / `question` atom(見上面「自產的 finding 要過一次獨立反駁」);那一步整步跳過時這一行寫跳過的理由。`nitpick` / `note` 沒有這一行。

**Follow-up 項一樣是 atom。** 同一組 `<icon> [F<n>] <label> · <category>` header、同樣要 `file:line`——`Follow-up` 分的是嚴重度,不是格式。寫成散文 bullet 時它讀起來像收尾的補充語句而不是一則 finding,使用者會整條略過,下一輪還要重講一次。(貼出去用 Template A 時 Follow-up 不帶 id——那是 arc 終點,見 `publish-format.md`;內部報告要帶,因為對話得指名它。)

**每一輪內部報告開頭先寫一行 ledger,列出至今每個 id 與它的狀態,後面接獨立反駁第二類的計數**:`累計 F1–F4:F1 撤、F3 撤、開放 F2 / F4;散文行 31 行 / 行為斷言 7 句:2 REFUTED、1 無法判定、4 CONFIRMED(3 則的引用落在 diff 外)`。計數那半是另一件事,不是 F-id 的一種——它記的是「這一輪掃了多少、判掉幾句」,格式與跳過時的寫法見上面〈交出去之前要過一次獨立反駁〉。F-id 那半是後面所有編號的對照物件——要提某一項時先在 ledger 找它的號,而不是憑印象重編;要開新項時取 ledger 上最大號 + 1。**被撤掉或被否決的號空著,不補、不回收**:回收會讓前面指名過的 `F<n>` 在後面指向另一件事,對話裡再也對不回去。ledger 同時擋掉另一半——一項在某一輪只用文字提到而沒帶號(「還開著的還有 scrapeTimeout 那條」),下一輪就沒有東西可查,號自然會漂掉。

**finding 的機制是分支或順序時,`根因＋解法` 不得只有散文**——必須帶一張 fenced ```text 圖,單欄(CJK 破壞多欄對齊),且圖上要看得到**分歧點**:只畫一條路徑等於沒畫,這類 finding 的內容正是「這條路走不到那一關」。缺 codeblock 是看得見的,不必先察覺自己講不清楚;散文要讀者在腦裡自己重建那棵樹,而樹是現成的。**圖是取代句子不是追加**——畫了圖,散文就該變短。實例:某則 finding 的機制是「未知檢查排在豁免判定之前,所以完整宣告的請求走不到豁免那三關」,第一輪寫成散文、連問三輪,第三輪畫出那棵樹(算 primary → 不在 slaves 就放行 → 三道宣告檢查 → 放行)才落地;那棵樹在讀完 code 的第一分鐘就在手上。貼出去時它跟著機制那半落在 `問題`,不在 `建議`(見 `publish-format.md` 的 atom 與 Template B)。

## Posting a review

Posting is a separate step the user must trigger (never automatic). The failure mode here has been posting ad-hoc prose — because the correctly-shaped artifact didn't exist yet and "then load `publish-format.md` and reformat" was a separate step that got skipped. So the shape lives here, in-context on skill load: **build the post from the skeleton below; there is no reload step to skip.** `references/publish-format.md` is the **source of truth** for the format (render hygiene, 篇幅, the full first-review Template B, multi-round composition) — the skeletons below are a convenience copy, so **when the two disagree, that file wins and these get corrected**. Load it before posting whenever the post needs anything the skeleton doesn't show.

The strongest form of this: for **Case 2b**, shape the report you present in conversation as Template C/A from the start. Then "post it" is a paste, not a reformat — the step that keeps getting skipped no longer exists. (2b discussion still happens in conversation; the user typically asks follow-ups.)

**Icon ↔ label** — one icon per item. The Conventional Comments label carries the type; blocking-ness is a separate `(blocking)` / `(non-blocking)` decoration, never a second icon stacked on the item:
🔴 issue (blocking) · 🟡 issue (non-blocking) · 🔵 nitpick · 💡 suggestion · ❓ question · 📝 note / chore · 👍 praise. On re-review, a prior finding's icon becomes its resolution status instead: ✅ 已解 · ⚠️ 部分/表面 · ❌ 未處理. `praise` 併進 verdict 行,不單獨成項。

**Template A — approve / arc endpoint** (Case 1/2a clean, or 2b fully resolved):

```text
LGTM 👍

<one-line verdict: direction right, mergeable>

## Review recap

<一到兩句：根因對齊 / 修法 + `file:line`。短到不需要自己的標題>

## Follow-up（非阻擋）

### <icon> <label>: <subject 一行>

問題：…
建議：… `file:line`

<收尾行：只在 Follow-up 非空時寫>
```

**兩個 `##` 節,finding 一律 `###`。** 粗體只是 `<p>` 裡的 `<strong>`、與內文同字級,撐不起層級;`####` 也只有間距沒有字級差(GitHub 的 `h4` 是 1em)。三個 template 的 finding 都在 `###`。

**不列閘門結果。** CI 綠不綠、regen 跑了沒、測試存不存在,是合併前閘門的產物、給使用者看的,review 輸出不再列一次;順手驗過而**本身構成 finding** 的寫進 Follow-up,只是「我看過了」的不寫。額外驗過的改動、作者自己列的未結事項同理——歸進對應的 atom 底下,不另開節(有了空章節就會拿機制描述去填,而機制是作者自己寫的)。作者做對的事客觀寫他做了什麼,不寫成「我沒發現的」。

**篇幅**:subject 一行,每條一查核點一行。讀者判準:作者不回頭看 diff,就能看懂什麼壞了、什麼條件下壞、怎麼修——由交報告前的冷讀執行(見〈Output model〉開頭)。`問題` 超過 2 句、`建議` 超過 3 句,或總長超過門檻(< 50 行 diff → 20 非空行;50–300 → 35)時,照砍的順序檢查一次:回述作者已知的事 → 同類項合併 → 展開的 atom 收回單行;砍完仍超過就保留,那是這條 finding 需要的長度。機制 codeblock 不計入——講不清時畫圖,不是多寫幾句。

**Template C — reply confirmation** (Case 2b with still-open items):

```text
## Review recap

前一輪 N 點：M 已解、K 待調整；新增 commit 一併看過。

### 逐點對照（對 commit 驗，非只看回覆）

- ✅ [F1] <label>: `<sha>` 守住 <invariant> `file:line`
- ⚠️ [F2] <label>: 回覆說 X，但 `<sha>` 只改表面，根因仍在 `file:line`
- ❌ [F3] <label>: 未處理 / 理解偏差 — <差在哪>

### 🔴 [F4] <label>: <這輪新發現>

問題：…
建議：… `file:line`

總判：全解 → 用 Template A 收尾 + approve；仍有 K 點 → 待下一輪，列是哪幾點
```

無新發現時在「逐點對照」後一行明寫「新 commit 未引入新問題」，不開空節。修正沒帶到相關 test / doc / callsite 時,那本身就是一個 finding,不設常設的「一致性」行。**F-id 從第一輪就編**，否則第二輪要 carry forward 時無從引用。

First-review (Case 2a) with open findings uses Template B — findings 掛在 `## Review recap` 下、用 `### <icon> [F<n>] <label>: <subject>` + 空行 + 問題 / 建議 + `file:line`。B 沒有「根因對齊」節、也沒有 catch-all 的「另：」;full form in `references/publish-format.md`.

Post via `gh pr review` (approve / request-changes / comment). To edit an already-posted review body: `gh api --method PUT repos/<o>/<r>/pulls/<n>/reviews/<id>` (PUT, not PATCH — PATCH 404s).

**回報貼了什麼時,引那次指令回傳的 review id 或時間戳。** 打不出一個沒收到過的 id,所以少了它在寫的那句話裡就看得見——這比事後另跑一次查詢確認便宜也可靠。要擋的是把**打算做的事寫成已經做了**:草稿寫完、還沒有任何 post 指令跑過並回傳結果,就不存在「已貼上去」這件事,那句話不准寫。
