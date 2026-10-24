# 演進模式（--evolve）完整流程

對照 Claude Code release notes，找出新功能或行為變更，提案更新自身 SKILL.md 的分析維度。隨版本演進，避免分析能力落後。

## Phase 1: 版本基準

1. 取得 installed version：`claude --version`
2. 決定 from version（依優先序）：
   - 若使用者帶 `--force-from <version>` 參數 → 直接用指定版本（**忽略所有 marker**）
   - 否則讀 `~/.claude/skills/x-session-learning/.last-evolved`
   - 若無：讀 `~/.claude/skills/x-cc-release-cfg-sync/.last-reviewed` 作為起點
   - 若皆無：installed version 往前 5 個 patch
3. to version = installed version
4. 若 from == to → 告知「無新版本」，中止
5. 若 from > to → 告知「from 版本高於 installed，請檢查參數」，中止

## Phase 2: 取得 release notes

逐版平行抓取：

```
WebFetch("https://api.github.com/repos/anthropics/claude-code/releases/tags/v{version}")
```

解析每個回應的 `body` 欄位作為 release notes 內容。每一版歸成下面三類之一，提案標頭列出後兩類各是哪幾版：

- **有內容** → 進 Phase 3
- **沒有內容**：404（該版沒有 release tag）、`body` 空白、或 `body` 只有「Bug fixes and reliability improvements」→ 略過。之後重抓結果也一樣，所以 marker 可以越過它
- **抓取失敗**：403、429（rate limit）、網路錯誤 → 改抓 `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`（約 1MB）取出對應段落：取得就視為有內容、進 Phase 3；CHANGELOG 也抓不到或沒有那一版的段落，這一版就算沒讀到，Phase 6 不寫 marker

404 與 403 都是「沒拿到東西」，但只有前者真的沒有內容。把抓取失敗當成沒有內容，marker 一越過去，那幾版之後就不會再被讀到。

## Phase 3: 過濾「x-session-learning 相關」signal

逐條 release note 對照下表，無命中跳過：

| Signal | 對應分析維度 |
|--------|-------------|
| 新的 skill/agent frontmatter 欄位（model, effort, allowed-tools, disallowed-tools, experimental.cacheTtl, ...） | Phase 3 配置與成本審視 |
| 新的 model 名稱、effort levels、context 上限變更 | Phase 3 配置與成本審視 / Phase 1 資料收集 |
| 新的 tool 或 tool 行為改變（Read, Edit, Bash, Agent...） | Phase 2 工具選擇 |
| 新的 hook event 類型 | Settings 優化 / Phase 5 建議產生 |
| 新的執行模式（background, schedule, defer, autonomous loop...） | Workflow patterns |
| 新 plugin 機制（plugin skill 路徑、bin/、新 settings 欄位） | Plugin skill coverage |
| 新的 subagent_type（Explore, Plan, ...）、Agent tool 參數、workflow subagent 的 env | Phase 2 工具選擇 + Subagent overrides |
| Memory 機制變更（auto-memory、type 規範） | Memory hygiene |
| Context 管理新功能（compaction、1M context、session resume） | Phase 2 Context 管理 |
| Transcript 記錄格式變更（新的 record 型別、`usage` 欄位、advisor 機制） | Phase 1 資料收集；gap 多半住在 transcript-parsing.md（advisor 見陷阱五、新 record 型別見陷阱六） |

## Phase 4: 比對自身 SKILL.md

1. Read `~/.claude/skills/x-session-learning/SKILL.md`
2. 對每個命中的 signal，搜尋 SKILL.md 是否已 cover（grep 關鍵字、檢查表格列、檢查 phase 結構）；Transcript 記錄格式那一類同時 grep references/transcript-parsing.md
3. 列出未 cover 的 gap，標注：
   - 應該新增的位置（哪個 phase / 哪個 sub-section）
   - 現有最接近的內容（用於評估「合併」vs「新增」）

## Phase 5: 提案

對每個 gap 產出修改提案，輸出格式如下（每個提案獨立呈現，避免巢狀 code block）：

**標頭**

```
## Session Learning Evolve Proposal
版本範圍: v{from} -> v{to}（N 個 release，命中 M 條）
沒有內容的版本: …；沒讀到的版本: …（沒有就省略該欄）
```

**每個提案的欄位**

- 提案編號 + 版本 + feature 名稱
- Release note 摘要（一句話）
- 對應分析維度（哪個 phase 哪個 sub-section）
- 現況（已有相近內容→建議合併；完全未涵蓋→建議新增）
- 建議修改位置（具體段落或表格列）
- 草稿內容（用獨立 diff/markdown code block 呈現，避免和外層巢狀）

AskUserQuestion 讓使用者選擇：
- **全部採納** — 自動 Edit 所有提案
- **逐項確認** — 每個提案個別 AskUserQuestion
- **跳過全部** — 不修改但仍更新 .last-evolved（避免下次重複看到相同 signal；Phase 2 有沒讀到的版本時不更新）

## Phase 6: 執行 + 更新 marker

1. 接受的提案逐個 Edit SKILL.md（合併型優先，避免結構發散）
2. 執行 SKILL.md〈修改後一致性審視〉章節的 Agent，範圍為 SKILL.md 加全部被引用的 reference
3. Write `~/.claude/skills/x-session-learning/.last-evolved` = `{installed_version}`——**Phase 2 有任何一版歸在「抓取失敗」而沒補到時不寫**，報告裡列出那幾版，下次 --evolve 從原 marker 重跑
4. 顯示變更摘要（修改的 section 列表）

## 注意事項

- **只修改自身 SKILL.md 與它的 references/**，不擴張到其他 skill
- **一致性審視照跑**，範圍為 SKILL.md 加全部被引用的 reference。不設「只動到無依賴段落就略過」的例外：判斷自己剛改的段落有沒有 reference 依賴，靠的正是出錯時失效的那份自覺；SKILL.md 現有多處以 reference 的量測結論為據，一邊改了另一邊沒跟上時沒有其他關卡會發現
- 若新 feature 與現有 sub-section 重疊，**優先合併**而非新增（保持結構簡潔）
- 跳過全部時也要更新 `.last-evolved`（Phase 2 有沒讀到的版本時除外），否則下次又重複看到。後悔時可：
  - `rm ~/.claude/skills/x-session-learning/.last-evolved` 清除 marker，下次 --evolve 從 x-cc-release-cfg-sync 的 `.last-reviewed` 起點重跑
  - 或用 `--evolve --force-from <version>` 指定起始版本，繞過 marker 一次性補課
- Phase 5 提案需保持 SKILL.md 整體在合理長度，發散時主動建議拆 reference 檔
- 與 x-cc-release-cfg-sync 的關係：兩者**獨立判斷**——x-cc-release-cfg-sync 看「使用者配置 vs release」，x-session-learning --evolve 看「分析能力 vs release」。可同時跑也可分開跑
