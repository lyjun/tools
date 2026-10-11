# Commit Reference

Detailed procedure for creating standardized commits. The branch-protection /
commit-rules guards in `SKILL.md` apply before any of this — confirm them first.

## Commit Message 規範

### 變更類型

| 類型 | 用途 | 範例 |
|------|------|------|
| **feat** | 新增使用者可見的功能 | `feat(auth): add login endpoint` |
| **fix** | 修復 bug 或 crash | `fix(retry): resolve timeout in retry logic` |
| **perf** | 可量測的效能改善 | `perf(query): add index for user lookup` |
| **refactor** | 重構程式碼，不改變行為 | `refactor(db): extract connection pool` |
| **test** | 僅變更測試檔案 | `test(auth): add login integration tests` |
| **docs** | 僅文件變更 | `docs(api): update authentication guide` |
| **build** | 建置設定（依賴、Dockerfile、Makefile、devcontainer） | `build(deps): upgrade to Go 1.21` |
| **ci** | CI/CD pipeline 設定 | `ci(test): add race detection to test workflow` |
| **chore** | 日常維護（.gitignore、git hooks、本地工具設定） | `chore: update .gitignore patterns` |
| **revert** | 還原先前的 commit | `revert: revert feat(auth): add login endpoint` |
| **style** | 僅格式調整（空白、auto-formatter） | `style(api): fix indentation` |

**類型常見混淆**:

| 容易搞混 | 判斷方式 |
|----------|----------|
| `feat` vs `fix` | feat = 全新功能；fix = 修正本該正常運作的行為 |
| `feat` vs `refactor` | feat = 新功能；refactor = 重構既有程式碼，行為不變 |
| `fix` vs `refactor` | fix = 修正 bug；refactor = 重構但無 bug 修正 |
| `fix` vs `test` | fix = 產品程式碼有 bug；test = 僅變更測試檔案 |
| `perf` vs `refactor` | perf = 有可量測的效能提升；refactor = 效能不變 |
| `build` vs `ci` | build = 編譯/環境相關；ci = pipeline 設定（test/deploy） |
| `build(deps)` vs `chore(deps)` | build = 影響編譯或執行的依賴；chore = 開發工具（linter、formatter） |
| `chore` vs `ci` | chore = 本地工具（`.gitignore`、git hooks）；ci = pipeline 設定（`.github/workflows`） |
| `revert` vs `fix` | revert = 完整還原先前 commit；fix = 修正特定 bug 而非還原 |
| `style` vs `refactor` | style = 僅格式（空白、排版）；refactor = 結構性變更 |

**`chore` vs `build` 常見錯誤**（影響編譯或執行環境的變更應為 `build`，非 `chore`）:

| 錯誤 | 修正 |
|------|------|
| `chore: update Makefile` | `build: update Makefile targets` |
| `chore: update devcontainer` | `build(devcontainer): update devcontainer config` |
| `chore: update Go version` | `build: update Go to 1.26.2` |

**多種變更類型時**: 選擇主要類型（feat+test → `feat:`，同 commit 內測試隨產品程式碼走）

### Scope 規則

**使用套件/模組名稱，禁止使用檔名。**

- `feat`、`fix`、`perf`、`refactor`、`test`、`build`、`ci` **必須**加 scope
- `docs`、`style`、`chore`、`revert` 跨多個套件時可省略
- **命名來源**: 套件名、模組名、功能區（如 `auth`, `db`, `api`, `cli`）
- **跨套件**: 一個為主用主要套件名；比重相當時省略 scope，在 body 列出套件；完全不相關的變更拆成多個 commit

### 標題規則

| 規則 | 說明 | 範例 |
|------|------|------|
| 長度 | 最多 50 字元（不含前綴） | — |
| 語氣 | 祈使語氣 | `add` ✓ / `adds` ✗ / `added` ✗ |
| 大小寫 | 前綴後小寫開頭 | `feat: add feature` ✓ |
| 標點 | 無句號結尾 | `fix: resolve bug` ✓ |

### Body 格式

Body **必須包含**，說明「為什麼」做這個改動。例外：極簡變更（修正錯字、調整格式）且 subject 已能完整說明意圖時可省略。

**每行最多 72 字元**，超過就手動換行。理由：`git log` 顯示 body 時左側縮排 4 格，72+4=76 仍落在 80 欄終端機內；不換行的整段 paragraph 在 `git log` / PR / `git blame` 介面會被迫橫向捲動或硬折，破壞可讀性。URL、無法斷開的字串可例外超出。

**禁止加上任何自動簽名**（如 `Co-Authored-By`、`Generated with Claude`）。

**禁止的訊息寫法** — 描述實際變更，不描述 review 過程：

| 禁止 | 改為 |
|------|------|
| "address code review feedback" | "add null check to prevent crash" |
| "fix PR comments" | "simplify error handling logic" |
| "apply suggestions" | "improve validation error messages" |
| "respond to review" | "extract middleware into separate package" |
| "per feedback/session/review" | 描述實際變更內容 |

**fix** 必須包含 Root Cause 分析:

```
fix(retry): resolve timeout in retry logic

Root Cause:
Caller's context was not passed to retry function. Each retry
created a new context with the same timeout, causing subsequent
retries to timeout immediately after the first failure.

Solution:
Pass parent context through retry chain and use context.WithTimeout
for each individual attempt, ensuring timeout applies per-attempt.
```

**feat** — 使用 `Changes:` + bullet list 列出實作項目

**refactor** — 使用 `Motivation:` 說明 WHY，再用 `Changes:` 列出項目

**Breaking Changes** — Scope 後加驚嘆號 (!)，Body 包含 `BREAKING CHANGE:` 標記:

```
feat(api)!: change token format from HS256 to RS256

BREAKING CHANGE: Existing tokens will be invalid.
```

---

## 執行流程

### 1. 分析與確認範圍

**務必跑 `git status` 確認工作區實際狀態**，不要依賴先前 tool 輸出假設工作區乾淨。平行執行:

```bash
git status --short             # 變更狀態 + untracked 檔案
git diff --stat                # 變更摘要（避免 build 產物的完整 diff）
git diff --cached --stat       # staged 變更摘要
git log --oneline -10          # 識別專案 commit 風格
```

**Staging 規則**:
- 使用者指定範圍（如「只 commit web/」）→ `git add <path>`
- 僅已追蹤檔案變更 → `git add -u`
- **禁止 `git add -A` 或 `git add .`**，除非使用者明確要求 commit 所有變更
- 有 untracked 檔案 (`??`) 時，先列出清單詢問使用者

### 2. Root Cause 分析（僅 fix 類型）

1. 讀取修改的程式碼理解變更
2. 搜尋相關 context（呼叫者、相關函式）
3. 識別根本原因（設計缺陷、錯誤處理、依賴問題）
4. 記錄 **WHY** 發生與 **HOW** 解決

### 3. 產生 Commit Message

1. 決定變更類型（依變更類型表判斷）
2. 決定 scope（依 Scope 規則判斷是否必須）
3. 比對 `git diff` 確認 body 涵蓋所有面向的變更（邏輯、路徑、常數、結構），避免遺漏
4. 撰寫標題（≤50 字元、祈使語氣）
5. 撰寫 body（fix 需 Root Cause）

### 4. 執行 Commit 與回報

使用 heredoc 保留格式:

```bash
git add <specific-paths> && git commit -m "$(cat <<'EOF'
feat(module): add new feature

Changes:
- Implementation detail 1
- Implementation detail 2
EOF
)"
```

**回報術語**:
- 「已建立 commit `<hash>`」— 僅在執行 `git push` 後才說「已推送至遠端」

### 5. PR Comment（使用者明確要求時）

使用者要求在 PR 留言時（e.g.「comment 在 PR 上」），commit 完成後執行：

```bash
gh pr comment <number> -b "<summary>"
```

- 摘要內容基於當前 session 的修正項目
- 格式：表格列出修正項目 + 驗證狀態

---

## Squash 流程（合併多個 commit）

### 觸發條件

使用者要求「合併 commit」、「squash」、「整合成一個 commit」等。

### 執行步驟

1. `git log --oneline -N` 確認合併範圍
2. `git show --stat <each-hash>` 分析每個 commit 的實際變更
3. **重新分類 type**：依本參考的變更類型表決定，禁止沿用原 commit 的非標準 prefix（如 `draft:`、`wip:` 等）
4. 撰寫合併後的 commit message（同標題規則 + Body 格式）
5. `git reset --soft HEAD~N` → commit → 驗證變更內容一致

> Rebase/amend 的 backup-tag 安全流程見 `workflow.md`。

---

## 故障排除

| 問題 | 解決方式 |
|------|----------|
| No changes staged | `git add -u`（已追蹤）或 `git add <files>`（新檔案） |
| Pre-commit hook failed | 修復後建立**新 commit**（勿用 `--amend`，原 commit 未成功） |
| 暫存檔案被誤加 | `git reset HEAD~1` 撤銷，改用 `git add <specific-path>` 重新 commit |
