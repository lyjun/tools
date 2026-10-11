---
name: arx-create-pr
description: Create PR with Git Flow branch naming, pre-submit checklist, and code quality gates
model: sonnet
---

# Create PR Skill

## PR Configuration
- **Assignees:** @me
- **Reviewers:** (none, select in GitHub UI)
- **Labels:** (choose one)
  - `enhancement` - New feature
  - `bug` - Bug fix
  - `documentation` - Documentation update
- **Branch Naming:** Follow Git Flow (`<type>/<descriptive-name>`)
  | Prefix | Use Case | Branch From | PR Target |
  |--------|----------|-------------|-----------|
  | `feature/*` | New features, non-urgent bug fixes, refactoring | `develop` | `develop` |
  | `release/*` | Release preparation, final testing and fixes | `develop` | `main` |
  | `hotfix/*` | Production emergency fixes | `main` | `main` + `develop` |

  Examples: `feature/user-authentication`, `hotfix/database-connection-leak`

  **Branch naming antipatterns** — reject and ask user to rename before continuing:

  | Wrong | Reason | Correct |
  |-------|--------|---------|
  | `feat/user-authentication` | Commit type is not a branch prefix | `feature/user-authentication` |
  | `fix/login-redirect` | Non-urgent fixes use `feature/*` | `feature/fix-login-redirect` |
  | `refactor/payment-service` | Refactors use `feature/*` | `feature/refactor-payment-service` |
  | `hotfix/add-dark-mode` | `hotfix/*` is only for production emergencies | `feature/add-dark-mode` |
  | `Feature/UserAuth` | Uppercase / camelCase | `feature/user-auth` |
  | `feature/JIRA-123` | Ticket number alone lacks description | `feature/jira-123-user-authentication` |

## PR Title
```
<type>(<scope>): <short description>
```
- Follow Conventional Commits format
- Keep under 72 characters
- Examples: `feat(auth): add user login API`, `fix(db): resolve connection leak`

## PR Description

```markdown
## Summary
<!-- 2-4 句連貫敘述：原本是什麼問題、為什麼會發生、這個 PR 怎麼解。
     用「因為 / 所以 / 一旦 / 這樣一來」把因果串起來，讓不熟這塊領域的
     reviewer 能順著因果讀懂。不要條列、不要用箭頭鏈(A → B → C)代替因果句、
     不要把三四個補充疊進同一個括號。 -->

## Changes
<!-- 具體改動，一項一行。各自獨立的查核點分行寫，不要用分號串成一長句 -->
-
-
-

## 流程 / 架構變更
<!-- 條件式章節：只在下方「何時保留」命中時留著，沒命中就整節刪除 -->

## 格式變更:before → after
<!-- 條件式章節：改動改變序列化 / 落地格式時保留，貼最小 before→after 對照；沒命中就整節刪除 -->

## Related Issues
<!-- Link to related issues: Closes #123, Fixes #456 -->

## Breaking Changes
<!-- List any breaking changes, or "None" -->

## Test Plan
<!-- How to verify the changes work correctly -->
- [ ] Unit tests pass
- [ ] Manual testing steps:
  1.
  2.

## Screenshots
<!-- If UI changes, add before/after screenshots. Otherwise delete this section -->
```

### 語言

Body 用台灣繁體中文寫。技術詞留英文——函式名、package 名、CLI flag、error code，以及在英文裡更精確的工程詞彙（`controller`、`reconcile`、`webhook`、`payload`、`retry`、`timeout`）都不要翻成中文。

採台灣用語，不要用中國大陸用語：程式非程序、伺服器非服務器、資料庫非數據庫、檔案非文件、函式非函數、設定檔非配置文件。簡體字一律不用。

PR title 不受這節影響，仍是英文 conventional commit，見上方 PR Title 段。

### 「流程 / 架構變更」節：何時保留

改動命中下列任一項時保留這節，並在裡面畫一張 ASCII 圖：

- 呼叫順序或執行序改變（原本 step B 在 step A 之前，現在調換）
- 新元件或新的一層進入既有 pipeline
- 跨子系統的資料流新增或移除
- 狀態機、生命週期被修改

沒命中就把整節刪掉。留一個空標題只會讓人拿機制描述去填，而機制在 `## Changes` 已經寫過了。

會畫圖是因為順序與分支用散文描述要四五句才講得清，一張圖加一兩行說明就夠，reviewer 掃一眼就知道動到哪一段。

畫圖規則：用 Unicode 框線字元（`─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ → ▼ ▶`），總寬度上限 255 字元。

**一律單欄，由上往下畫**，不要左右並排 before / after。中文字在等寬字型下是雙寬，只要有一個中文出現在某一列的欄與欄之間，那一列的右欄就會比其他列偏移，整張圖看起來是歪的。中文註解要放就放在整列最右邊。

**執行序調換：**

```
修改前
updateSystemData
      │
      ▼
setPendingAction        ← 先設 merge trigger
      │
      ▼
updateGrubEnv           ← boot_slot 後寫，寫失敗就對錯誤 slot 合併

修改後
updateSystemData
      │
      ▼
updateGrubEnv           ← boot_slot 先寫入
      │
      ▼
setPendingAction        ← 再設 merge trigger
```

**新元件進入 pipeline：**

```
firmware archive
      │
      ▼
verifyFirmwareArchive
      │
      ├─▶ writePartitionImages  (kernel / root)
      ├─▶ updateESP             (ESP partition)
      ├─▶ updateSystemData      (data.img) ← 新增
      ├─▶ updateGrubEnv         (boot_slot)
      └─▶ setPendingAction      (arx_pending_action)
```

### 「格式變更:before → after」節：何時保留

改動改變一個序列化或落地格式時保留這節，貼一段最小的 before→after 對照（`diff` 區塊或並排的最小片段），不要只用散文描述：

- config schema / 設定檔內容（欄位增減、預設值改變）
- proto wire、API payload 的欄位或型別
- DB schema / migration
- 程式寫進磁碟的格式其內容形式改變（如 `/etc/pam.d/*`、systemd drop-in、產生出來的設定檔）

沒命中就整節刪掉。附 before→after 是因為格式改動的重點在「形狀哪裡變了」——欄位搬去哪、語意有沒有換、哪些 key 消失——一段資料對照比散文快，reviewer 與作者都能一眼對上，不必自己從 diff 拼回來。

這節與上面「流程 / 架構變更」正交：那節畫的是控制流與時序，這節貼的是資料形狀。同一個 PR 可能兩節都命中、也可能都不命中。

---

## Workflow

### Step 1: Collect branch context

```bash
CURRENT_BRANCH=$(git branch --show-current)
echo "Branch: $CURRENT_BRANCH"

# Detect base branch: try develop first (Git Flow), then main, then remote HEAD
if git rev-parse --verify develop >/dev/null 2>&1; then
  BASE="develop"
elif git rev-parse --verify main >/dev/null 2>&1; then
  BASE="main"
else
  BASE=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
fi
# Compare against the remote base, not the local branch: a stale local develop
# would count commits that landed upstream as this branch's own.
git fetch origin "$BASE" --quiet
RANGE="origin/$BASE...HEAD"
echo "Base: $BASE"
echo "Diff range: $RANGE"

echo ""
echo "=== Changed files ==="
git diff --name-only $RANGE

echo ""
echo "=== Commits ==="
git log --oneline $RANGE

echo ""
echo "=== Uncommitted changes ==="
git status --porcelain
```

**Early termination:**
- If uncommitted changes exist, inform the user to commit first and stop.
- If no commits in range, inform the user and stop.

### Step 2: Base sync check

Ensure the branch is up-to-date with the base before running quality gates — stale bases cause false-green builds.

```bash
git fetch origin $BASE --quiet
BEHIND=$(git rev-list --count HEAD..origin/$BASE)
echo "Behind base by: $BEHIND commits"
```

- Behind by > 0 → warn the user and recommend rebasing before proceeding. Ask via AskUserQuestion:
  - **Rebase now** — run `git rebase origin/$BASE`, then continue to Step 3
  - **Skip, proceed anyway** — continue to Step 3 (user accepts the risk)
  - **Stop** — abort the PR creation

### Step 3: Run quality gates

Run sequentially. Use `devcontainer exec` if a devcontainer is active.

```bash
make lint
make test
make build
grep -q '^docs:' Makefile && make docs
```

**If any gate fails**, report the failure and stop. Do not proceed to PR creation with failing gates.

After `make docs`, check for uncommitted changes (`git diff --name-only`). If generated docs changed, report them and stop — the user needs to commit these changes first.

### Step 4: Documentation completeness check

Only check if this PR introduces a **new user-facing feature or flow** (not for bug fixes, refactors, or internal changes). Determine this from the commit messages and branch name.

If it is a new feature, ask the user:

> 這個 PR 新增了使用者可見的功能。是否需要更新手寫文件（README、architecture docs、flow docs 等）？

Use AskUserQuestion with options:
- **需要，我先補** — Stop here
- **不需要** — Proceed to Step 5

### Step 5: Pre-submit checklist verification

```bash
# Commit count
COMMIT_COUNT=$(git rev-list --count $RANGE)
echo "Commits in PR: $COMMIT_COUNT"

# Diff size (excluding tests)
DIFF_LINES=$(git diff --stat $RANGE -- ':!*_test.go' ':!*_test.ts' ':!*.test.*' | tail -1)
echo "Diff size (excl. tests): $DIFF_LINES"
```

Flag issues:
- Commits > 5 → suggest squashing
- Diff lines > 500 (excluding tests) → warn about PR size

### Step 6: Create the PR

> 建立 PR 前若尚未審視變更，建議先跑 `/x-code-review`（correctness/security）與 `/x-code-improvement`（reuse/altitude/quality/efficiency）。

**Draft the PR description** using the template from the PR Description section.
Review the full commit messages (`git log --format="%B" $RANGE`) for structured
information (root cause analysis, error logs, references, limitation notes) that
should be included in the PR body — do not reduce these to a one-line summary.

Before finalising, walk the diff against the four「流程 / 架構變更」保留條件 and either
fill that section with a diagram or delete it. Deciding this from the diff is the point —
the section is easy to leave empty precisely when the change is the kind that needs it.

Do the same for the「格式變更:before → after」保留條件 — if the diff changes a
serialized / on-disk format (config schema, proto wire, API payload, DB schema, or a
file the code writes such as `/etc/pam.d/*`), fill that section with a minimal
before→after block; otherwise delete it. A directive / format string that changes shape
is exactly the case that reads as "just an internal edit" in `## Changes` and gets no
before→after unless this check forces the decision.

Determine the PR target branch from the branch prefix:
- `feature/*` → `develop`
- `release/*` → `main`
- `hotfix/*` → `main`

If the branch name does not match any of these prefixes, inform the user and ask them to specify the target branch via `AskUserQuestion` before proceeding.

Push and create the PR:

```bash
git push -u origin $CURRENT_BRANCH
```

```bash
gh pr create \
  --base <target-branch> \
  --title "<title>" \
  --assignee @me \
  --label "<label>" \
  --body "$(cat <<'EOF'
<PR description from template>
EOF
)"
```

Return the PR URL to the user.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Summary 寫成條列或箭頭鏈 | 改成 2-4 句連貫敘述，先講問題與成因再講解法 |
| 多個獨立查核點用分號串成一長句 | `## Changes` 一項一行 |
| 用簡體字或大陸用語（程序、服務器、數據庫、文件） | 改台灣用語（程式、伺服器、資料庫、檔案） |
| 把 `controller` / `reconcile` / `payload` 翻成中文 | 技術詞留英文 |
| 執行序或 pipeline 有變動卻沒畫圖 | 補「流程 / 架構變更」節與 ASCII 圖 |
| 改動沒命中四個條件卻留著空的「流程 / 架構變更」節 | 整節刪除 |
| ASCII 圖超過 255 字元寬，或中文放進並排欄位 | 拆圖，含中文時改單欄 |
| 改了序列化 / 落地格式（config、proto、payload、`/etc/pam.d/*` 等）卻只在 `## Changes` 描述，沒貼 before→after | 補「格式變更:before → after」節與最小對照片段 |
