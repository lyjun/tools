# Session Learning Checklist

效率檢查的完整清單。

---

## 平行化

| 問題訊號 | 改進 |
|---------|------|
| 2+ 個連續訊息各執行 1 個 tool | 合併為單一訊息平行執行 |
| 已知要讀 A, B, C 卻分次讀取 | 一次性平行讀取 |
| git status, diff, log 串列執行 | 平行執行 |

## 工具選擇

| 操作 | 應使用 | 違規 |
|-----|--------|------|
| 讀取檔案 | Read | bash cat/head/tail |
| 編輯檔案 | Edit | bash sed/awk |
| 寫入檔案 | Write | bash echo > |
| 路徑未知的大範圍搜尋 | Agent Explore | 在主對話對未知路徑反覆搜尋（目標明確、路徑已知時留在主對話才是對的） |

## Context 管理

| 問題訊號 | 影響 |
|---------|------|
| 同檔案讀取 2+ 次（未修改） | Token 浪費 |
| 主對話搜尋結果 > 2000 tokens | Context 污染 |
| 開放式問題未使用 Agent Explore | Token + 延遲 |

## 規劃效率

| 問題訊號 | 影響 |
|---------|------|
| 未讀設計文件直接實作，事後發現不符架構 | 返工 + Token 浪費 |
| 未確認需求就動手，中途改方向 | 返工 + 延遲 |
| 多步驟任務未建 task list，遺漏步驟 | 重複探索 + 延遲 |

## 搜尋策略

| 問題訊號 | 影響 |
|---------|------|
| grep pattern 過廣（如單字母、常見詞），結果 > 50 筆 | Context 污染 |
| 搜尋方向錯誤導致 3+ 輪無效搜尋 | Token 浪費 + 延遲 |
| 未用 --include 或路徑限縮檔案類型，搜尋範圍過大 | Token 浪費 |
| 已知檔案路徑仍用 grep 搜尋而非直接 Read | 不必要的間接 |

## Edit 效率

| 問題訊號 | 影響 |
|---------|------|
| old_string 匹配失敗後未 Read 就重試 | 連續失敗 + Token 浪費 |
| 同檔案相距 < 50 行的 3+ 次小範圍 Edit 未合併 | 多輪往返 |
| Edit 成功後重新 Read 同檔案驗證 | Token 浪費 |

## Settings 優化

偵測可透過 `settings.json` 消除的重複 friction。

### Permissions

| 問題訊號 | 建議 |
|---------|------|
| 同類 Bash 指令被使用者 reject/allow 2+ 次 | 加入 `permissions.allow` |
| 危險操作被重複執行且不應允許 | 加入 `permissions.deny` |
| 跨目錄操作被擋 (Read/Edit 目標在工作目錄外) | 加入 `permissions.additionalDirectories` |

### Hooks

偵測後依以下優先級建議:
1. **先確認 rules 覆蓋** — 問題是否已有 rule 但仍違反?
2. **rules 已存在但仍重複違反 → 建議 hook** — 作為強制手段
3. **重複手動操作 → 建議 PostToolUse hook** — 自動化取代人工

| 問題訊號 | Hook 類型 | 建議 |
|---------|----------|------|
| 特定 tool 執行後重複手動跑相同指令 | PostToolUse | 自動執行該指令 |
| rule 已存在但仍重複違反同類問題 | UserPromptSubmit | 注入提醒強化約束 |
| 特定 tool 操作前需檢查前置條件 | PreToolUse | 條件不符時 block |

### 環境變數

| 問題訊號 | 建議 |
|---------|------|
| session 中重複設定相同環境變數 | 寫入 `settings.json` 的 `env` 欄位 |

---

## Quick 模式優先檢查

1. 連續 3+ 個單一 tool call 可平行化?
2. 路徑未知卻在主對話反覆搜尋，應改用 Agent Explore?
3. 重複讀取未修改檔案?
4. 用 bash 讀寫檔（cat / sed / echo >）而非 Read / Edit / Write?
5. 搜尋結果累積 > 2000 tokens?
6. 未讀設計文件直接實作導致返工?
7. grep pattern 過廣導致大量無關結果?
8. 同檔案相距 < 50 行的多次小 Edit 可合併?
9. 同類指令被 reject/allow 2+ 次,可加入 permissions?
10. 特定 tool 後重複手動跑相同指令,可加 PostToolUse hook?
