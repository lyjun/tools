---
name: x-session-learning
description: Analyze session efficiency and generate improvement suggestions
user-invocable: true
model: sonnet
---

# Session Learning

分析 session 執行效率與配置成本，產出改善建議。支援單次 session 診斷、跨 session friction 回顧、以及隨 Claude Code 版本演進的自我更新。

## 使用時機

- **預設/--quick**：Session 結束回顧、Token 用量異常
- **--review**：定期回顧配置有效性（facets 調整現有配置 + report.html 評估新增需求 + friction 趨勢）
- **--evolve**：Claude Code 版本更新後，對照 release notes 補齊自身分析維度
- **避免**：任務進行中、簡單問答、首次使用（缺乏對比基準）

## 參數

| 參數 | 說明 |
|------|------|
| （無） | 完整分析 |
| `--quick` | 僅 Top 3 建議 |
| `--review [N]` | 回顧最近 N 天的 friction 資料並產出改善建議（預設 7 天） |
| `--evolve` | 對照 Claude Code release notes，提案更新自身 SKILL.md |
| `--evolve --force-from <version>` | 強制從指定版本掃描，忽略 marker（補課用） |

---

## 預設模式

### 分析流程

#### 1. 資料收集

資料源是 `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`。**開始解析前先讀 [transcript-parsing.md](references/transcript-parsing.md)**：該檔記錄六個解析陷阱，其共同性質是產生錯誤數值而非拋出錯誤，因此不會在執行時被發現。

統計當前 session。下面的 token、Advisor、輪次、Duration、Tools、per-skill turn 只取 `type == "assistant"` 的 record：Tools 與輪次不限定會被灌水（reference 陷阱六），其餘一併限定，讓所有計數取自同一批 record。User pushback 訊號不在此限，來源照它那一條：

- **Per-model token 分布**：依 model 列出 input / output / cache_create / cache_read。先按 `message.id` 去重再加總
- **Advisor 成本**：advisor 的 token 不在頂層 `usage`，只在 `usage.iterations[]` 裡 `type == "advisor_message"` 的項目，帶自己的 `model`。去重後另列一行，不併進 session model 分布與 cache 分母（理由見 reference 陷阱五）
- **Cache 效率**：`cache_read / (cache_read + cache_create + input)`，反映 context 重用率；低於 60% 為警示
- **輪次**：去重後的 assistant turn 數
- **Duration**：wall duration（首末 turn 的 `timestamp` 差）
- **Tools**：各類型次數、平行化比例（同一 `message.id` 內有 2+ 個 `tool_use`；先依 `(message.id, block.id)` 去重，且 message 順序表要用獨立的 `seen` 集合，兩者缺一都會讓次數翻倍——見 reference 陷阱二）。**判定平行化不足前，先看那些單一 Bash 呼叫的 `command` 字串有沒有 `for `／`while `／`; do`**：用 shell 迴圈在一次呼叫內跑完 N 個對象，省下的 tool turn 與 N 個平行呼叫相同，計為已批次而非平行化失敗。漏掉這個判斷會產出「把批次拆成多個平行呼叫」的建議，那與 `file-operations.md` 的 read-once 原則相反
- **Per-skill turn 數**：取 `attributionSkill` 欄位。這是 skill 的成本歸因基準；`Skill` tool_use 的次數只反映觸發頻率，不含該次觸發之後延續的 turn
- **User pushback 訊號**：取兩個來源的聯集（`type=user` 的字串訊息、`queue-operation` 的 `enqueue`），條件與理由見 reference。**逐則閱讀並分類，不使用 substring 詞表比對**：推翻的語言形式是否定加語氣詞（「打版本不是我們的事情吧」）與反問（「為啥這個不是整合到 X ?」），不是固定詞彙，因此詞表的召回率不隨詞數增加而改善。每則標為「推翻 / 澄清 / 一般指示」，推翻的項目對齊 `attributionSkill`，統計 per-skill 推翻次數，feed 到 Phase 3「Skill output discipline」維度

#### 2. 執行效率審視

依 [checklist.md](references/checklist.md) 檢查：
- 平行化（連續單一 tool call、批次讀取、Git 操作）
- 工具選擇（專用 tool vs bash、Agent Explore 使用、subagent_type 是否得當）
- Context 管理（重複讀取、搜尋累積、session 長度）

#### 3. 配置與成本審視

**前置：讀取配置（不只列檔名，要 Read frontmatter）**

```
Read settings.json，取得 enabledPlugins 列表
Read 每個 ~/.claude/skills/*/SKILL.md 的 frontmatter（讀到第二個 `---` 為止，不要用固定行數）
Read 每個「啟用中」plugin 的 SKILL.md frontmatter：
  - 路徑形如 ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills/<skill>/SKILL.md
  - **僅讀 enabledPlugins 對應的 plugin**，不掃整個 plugins/ 目錄（cache 含未啟用的版本）
ls ~/.claude/agents/*.md
```

只列檔名無法評估配置妥當性，必須 Read 取得 frontmatter。**不要用固定行數截斷**：多行 `description: >` 會把 `model:` 推到第 10 行之後，截斷後會誤判成「這支 skill 未宣告 model」，然後在下面「Skill model 配置」那一維產出一條假建議。

**審視維度**

| 維度 | 檢查內容 |
|------|----------|
| Skill model 配置 | model 與任務複雜度匹配（純 loader → haiku；推理/寫作 → sonnet） |
| Skill effort 配置 | 合法值分歧已於 2026-08-24 結案：官方文件為 `low / medium / high / xhigh / max`，`arx-cluster-ops` 原本的 `normal` 無效，已改為 `medium`。但 `effort:` 對 inline 呼叫是否生效仍未解——本機 2026-08-19 量測說不生效，v2.1.241 定向實測說生效（兩邊記錄見 `x-cc-config-guide` 的〈Effort 限制〉）。因此**仍不產出 effort 相關的成本建議**，直到重跑量測分出勝負。release note 有兩條直接相關：v2.1.267 修了 effort 被釘住的 model 忽略 `effort:`，v2.1.295 修了 Skill tool 提早結束時丟掉 `effort`。重測時，skill 的宣告值要同時不同於 session 的 `effortLevel` 和 `modelSettings` 的 per-model 值，否則量不出差別 |
| **frontmatter model 依呼叫路徑決定生不生效** | 2026-09-06 於 v2.1.263 複驗（方法與數據見 [transcript-parsing.md](references/transcript-parsing.md)）：使用者打 `/skill` 開一整輪**會**切換到宣告的 model；模型在回合中途用 Skill tool 載入的**不會**，整輪維持 session 的 model。判別依據是 transcript 有沒有一筆 `type=user`、`isMeta` 不為真、`message.content` 為字串且含 `<command-name>/<skill></command-name>` 的記錄，不是使用者有沒有打斜線，也不是 grep `<command-name>` 的命中數（tool_result 與 skill 內文裡的同名字串也會命中）：2026-10-11 一個 session 打了 `/x-session-learning --evolve`，沒有這筆記錄，第一個 turn 是 `Skill` tool_use，整段跑 `claude-opus-5-5`（宣告 sonnet）。為什麼這次沒走 slash 路徑，未驗。**effort 那半不在本列**——狀態未解，見上一列與 `x-cc-config-guide`〈Effort 限制〉。由此得出兩點判讀：per-model 分布無法指認**自動觸發的** skill 跑在哪個 model 上（那些 turn 一律等同 session），但 slash 開起來的那一輪可以，非 opus 的 turn 就是它；frontmatter 未設 `model:` 時仍建議補上，對自動觸發的 skill 是意圖聲明，對會被當指令打的 skill 才是實際成本控制 |
| Subagent model overrides | skill 內部 spawn Agent subagent 時是否指定 model（如 haiku 主 skill spawn `model: sonnet` 做重 task）。**subagent 的行為無法由本資料源判定**——`isSidechain: true` 的 record 在全部 session 中是 0 筆，subagent 的 turn 不寫進這些 JSONL。上一列的結論只涵蓋 inline 呼叫，不要外推到 subagent。spawn 時若帶了 `effort`（v2.1.292 起 Agent tool 支援），確認是使用者或 skill 明確要求的——Agent tool 規定未被要求時不設，所以「沒指定」不是缺口；workflow agent 的 model 另看 settings `env` 有沒有設 `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL`（v2.1.296） |
| Skill tool 限縮（disallowed-tools） | 唯讀性質的 skill（審查、分析、僅產出報告）是否用 `disallowed-tools` 排除 Write/Edit/Bash 等有副作用的 tool，作為降低誤操作與成本的手段；讀取 frontmatter 時一併檢查此欄位是否存在、是否涵蓋該 skill 實際不該碰的 tool |
| Plugin skill coverage | enabledPlugins 列出的 plugin skill 是否被納入分析；plugin SKILL.md 通常無法修改，僅作認知 |
| Workflow patterns | Bash 前景長時間等待（非 subagent）→ run_in_background；重複手動操作 → /schedule；長 session → /compact 或新 session。**Agent tool 呼叫的 subagent 自 v2.1.198 起預設已是背景執行**，「session 呆等 subagent」不再是這條建議該抓的訊號，不要對已背景執行的 subagent 呼叫產出「改用 background」這類建議 |
| Triggering 精準度 | description 過寬導致誤觸（耗 token）；過窄導致漏觸（重做工作） |
| Memory hygiene | auto-memory 寫入是否符合 type 規範；MEMORY.md 行數成長趨勢 |
| **Skill output discipline** | 對照 Phase 1 user pushback 統計：單一 skill 在 session 中被推翻 ≥ 3 次 → flag 該 skill 缺 pre-finding verification gate。建議：補 finding 出口紀律，結構照 `x-pr-review` SKILL.md「Pre-finding verification gate」——關卡清單、分級、drop-not-downgrade 原則都以那份為準，這裡稱名不重述（重述一份會漂的副本，正是它自己那一關要擋的）|

每項命中後產出 finding，feed 到 Phase 4 影響評估。

#### 4. 影響評估

| 嚴重度 | Token 浪費 | 延遲影響 |
|--------|-----------|----------|
| High   | >10%      | >3 輪    |
| Medium | 5-10%     | 1-2 輪   |
| Low    | <5%       | <1 輪    |

成本面 finding 額外標注：
- **Cost-Latent**：配置錯誤，本 session 未觸發但未來會發生（如 skill 沒設 `model:`，就只能跟著 session 跑 opus——不論 inline 生效性的複驗結果為何，沒設值都不會有別的行為）

#### 5. 建議產生

**比對原則**

產生每一條建議前，必須執行：
1. Grep 建議涉及的關鍵字，搜尋前置探索的所有位置（`CLAUDE.md`、`~/.claude/rules/`、`~/.claude/skills/`、`~/.claude/agents/`、`~/.claude/commands/`、`~/.claude/plugins/`、`~/.claude/projects/*/memory/`）
2. 確認沒有現有配置已覆蓋相同行為
3. 若有現有覆蓋 → 評估強化現有 rule，而非新增
4. 若無覆蓋 → 才加入建議清單，並標注「新增」vs「現有強化」

**最小修復原則**

- 一個 root cause = 一個修改位置
- 禁止因「關聯到」就發散修改

**因果宣稱要指得出證據**

上面兩條決定改哪裡，這條決定寫進去的內容能否成立。建議或草稿中每一句「做 X 會導致 Y」，在寫入檔案前要指得出本次 session 中驗證它的指令與輸出；指不出來就縮寫成已驗證的部分，或不寫。判準見 `x-user-rules.md` §6 Work Loop——用最便宜的真實訊號確認假設；此處是把它套用到本 skill 自身的產出。

理由是配置檔沒有複驗機制：寫入的敘述每個 session 都會被載入並當作既有事實使用，推論錯誤不會自行浮現。以下兩個實例都是未經執行的推論被當成結論寫入。

| 實例 | 錯在哪 | 為什麼會錯 | 改成什麼 |
|---|---|---|---|
| `x-git-ops/references/workflow.md` 的 upstream 條目 | 寫「裸 `git push` 會推上保護分支」 | 由「upstream 被設到保護分支」推導，未實際執行。預設的 `push.default=simple` 會因分支名不符而拒絕，只有 `push.default=upstream` 才會推上去 | 改列三種後果：`git pull` 靜默 merge、`@{upstream}` 對錯的基準報 ahead/behind、`push` 的行為依 `push.default` 而異 |
| 分析報告的 token 數字 | 數值為實際值的兩倍以上 | 逐行加總 `usage`，未依 `message.id` 去重；streaming 會重複 emit 同一筆 | §1 改為先分組去重，解析細節與對照數據移入 [transcript-parsing.md](references/transcript-parsing.md) |

**分類輸出**

| 分類 | 輸出位置 | 說明 |
|------|----------|------|
| 配置更新 | `CLAUDE.md` 或 `~/.claude/rules/` | 行為規範/約束 |
| Settings 優化 | `~/.claude/settings.json` | permissions, hooks, env, model 預設、effortLevel |
| Skill 調整 | `~/.claude/skills/` | 內容調整 + frontmatter (model/effort/disallowed-tools) 配置 |
| Agent 推薦 | `~/.claude/agents/` | 可獨立處理的事務流程 |
| Command 推薦 | `~/.claude/commands/` | 可透過 /command 觸發的工作流程 |
| Workflow 重構 | session 行為 | Bash 前景等待 → background（subagent 已預設背景，不在此列，見審視維度表的 Workflow patterns）；手動 → schedule；長 session 切分 |

**驗證原則**

建議修改現有 skill/agent 前，先確認本次 session 有實際使用（檢查相關 tool calls）。

例外：
- 建議新增 skill/agent/command（因缺少導致效率問題）
- 修改全域規則（CLAUDE.md、rules/）
- **Cost-Latent 類別**——配置錯就是錯，即使本 session 沒觸發

#### 6. 知識捕獲

回顧 session 中的 tool call 序列，識別可封裝的模式：

| 訊號 | 判定 | 建議 |
|------|------|------|
| 同一多步驟流程（3+ 步）在 session 中出現 2+ 次 | 重複程序性知識 | 封裝為 skill 或 agent（見下方決策） |
| session 中發現的 debugging pattern 或 domain insight | 可跨 session 複用的經驗 | 建議寫入 MEMORY.md |
| 現有 rule 過於複雜（含多步驟流程/腳本），更適合作為可載入的程序性知識 | rule 與 skill 邊界錯置 | 建議從 rule 遷移為 skill；只是單一具體陷阱（某指令的行為、某路徑）的，移到放具體條文的 rule 檔（如 `tool-constraints.md`），不必變成 skill |
| 同一 skill 的輸出被推翻達「Skill output discipline」維度的門檻（依 Phase 1 逐則讀出來的分類，不是比對詞表） | skill 缺 verification gate，紀律破洞 | 提議在該 skill SKILL.md 加 pre-finding verification 段落，關卡清單與分級以 `x-pr-review` 的那份為準，不在這裡重述份數。引用本 session 被推翻的具體 finding 當 anti-pattern 範例（讓未來讀 SKILL.md 的 reviewer 看得到實例）。參考 `x-pr-review` SKILL.md 的對應段落為結構範本 |

**Skill vs Agent 決策**

1. 流程需要使用者互動或決策判斷？ → **Skill**（使用者觸發、引導執行）
2. 流程不需互動、結果可預測可驗證？ → **Agent**（可 delegate 獨立完成）
3. 無法明確歸類 → 預設為 **Skill**

**新 skill/agent 的 model 配置**

每個新增建議必須附 model 推薦。它是不是真的省到錢，看這支 skill 怎麼被叫起來（2026-09-06 於 v2.1.263 複驗，見「配置與成本審視」那節）：走 slash 路徑的（transcript 有 `<command-name>` 記錄，判別見審視維度表「frontmatter model 依呼叫路徑」那一列），宣告值真的生效；靠 description 自動觸發、由模型中途載入的，寫了不代表省到錢，只是意圖聲明。兩種情況都要寫，因為讀的人要知道這支該用什麼等級。

| 任務性質 | 建議 model |
|---------|-----------|
| 純 orchestration / file loader / reference loader | `model: haiku` |
| 簡單摘要 / 格式化 | `model: haiku` |
| 推理 / 寫作 / 跨檔分析 | `model: sonnet` |
| 深度 reasoning / 複雜決策 | `model: opus`，frontmatter 注解原因 |

判定流程：
1. 對每個候選模式，檢查 `~/.claude/skills/` 和 `~/.claude/agents/` 是否已有覆蓋（含 plugin 來源）
2. 未覆蓋 → 依上方決策加入建議清單，附 model 配置
3. debugging pattern / domain insight → 建議寫入 `MEMORY.md`（附具體內容草稿）

### 輸出格式

```markdown
## Session Learning Report

**Token**: Xk input / Xk output / Xk cache_create / Xk cache_read（依 `message.id` 去重後；不寫「用了幾 %」——`usage` 沒有 context window 佔用的欄位，累計值算出來的百分比沒有意義）
**Model**: <session model> × N turns（有多個 model 才逐一列。**出現 haiku 或 sonnet 的 turn 屬預期內**——那是使用者打 `/skill` 開的那一輪跑在該 skill 宣告的 model 上，見 [transcript-parsing.md](references/transcript-parsing.md) 的複驗段；標注是哪一支 skill 即可，不必重跑量測）
**Advisor**: N 次 / Xk input / Xk output（<model>；不計入 Model 與 Tools 行——advisor 是 `server_tool_use` 不是 `tool_use`；沒有 advisor 呼叫就省略這行）
**Cache hit**: X%（低於 60% 請注意）
**Duration**: Xm（wall）
**Tools**: Read(A), Bash(B), Agent(C)
**Per-skill turns**: skill-a(N), skill-b(M)（無 skill 觸發則省略）
**效率評級**: Good / Needs Improvement / Poor

### 發現問題

#### 執行效率
1. [High] 問題描述 → 影響量化
2. [Medium] ...

#### 配置與成本
1. [Cost-Latent] 配置錯誤但本 session 未觸發 → 風險說明（如 skill 未宣告 model 的缺漏——是否真的省到看呼叫路徑，見 transcript-parsing.md 的複驗段；settings 的 `effortLevel` 與任務不匹配）

### 建議
1. Settings 優化（permissions / hooks / env / model 預設 / effortLevel）
2. 配置更新（rules / CLAUDE.md，附 diff）
3. Skill 調整（含 frontmatter model/effort/disallowed-tools）
4. Agent 推薦
5. Workflow 重構（Bash 前景等待改 background、schedule 改造、session 切分）

### 知識捕獲
- Skill 候選：`skill-name` — 用途描述（觸發條件、建議 model）
- Memory 候選：pattern 摘要（建議寫入 MEMORY.md 的內容草稿）
（無候選時省略此區塊）

### 待確認
- [ ] 調整 1: ...
- [ ] 調整 2: ...
```

報告只放有證據的 finding 與可執行的建議，沒有內容的區塊省略。

**產出前對帳**：各工具次數加總必須等於 total tool calls，且兩個數字都取自同一次 `message.id` 分組的結果。對不上代表中途換過解析方式，數字是錯的而不是誤差——重算，不要兩種算法的數字並排放進同一份報告。

這個檢查對「兩個數字同源」的錯誤無效：分組寫錯時分項與總數會一起錯而仍然相等，對帳照樣通過。見 [transcript-parsing.md](references/transcript-parsing.md) 陷阱二的 221 / 467 / 225 對照——tool call 總數要另外用一次獨立算法覆驗，不能只靠這條加總。獨立算法可用 `type=user` record 裡 `tool_result` 的不重複 `tool_use_id` 數；陷阱六的灌水用這個方法抓得到（該節表中第三欄）。

### 修改後一致性審視

使用者確認「待確認」清單並完成所有檔案修改後，spawn Agent subagent 執行跨檔案一致性審視。

```
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  prompt="審視以下檔案的一致性。以配置檔為主；修改清單含 scripts/ 時另做第 5 項，不審視程式風格與演算法。

修改清單：[列出所有新增/修改的檔案路徑，各附一句改了什麼]
對照檔：[未修改但已知相關的檔案，例如被引用的 reference、宣告同一機制的其他 skill、被指為判準來源的 rule]

讀完全部檔案後檢查：
1. 重複：不同檔案是否定義了相同或高度重疊的規則 → 指出應合併到哪一處
2. 跨檔矛盾：修改清單彼此之間、以及修改清單與對照檔之間是否有互相衝突的指示 → 指出衝突點
3. 關聯遺漏：修改 A 是否應連動更新 B（如 skill 引用了 rule 中已改名的概念，或 frontmatter 改了但內文流程仍依舊假設）→ 列出遺漏
4. 同檔案內部矛盾：新增內容與同一檔案中未被修改的既有段落是否打架 → 逐節掃過，不要只看新增段落
5. 修改清單含 `scripts/` 下的檔案時：每一條 exit 路徑（含未預期的例外）都印 `VERDICT:`；讀到殘缺資料不得報 ok；輸出不含「接下來該怎麼做」——對照 `~/.claude/skills/x-cc-config-guide/SKILL.md`〈script 的失效形狀〉

第 2 項的對照檔與第 4 項是最容易漏的兩類：前者因為衝突的另一半不在修改清單裡，後者因為注意力集中在新寫的段落。

輸出格式：問題清單，每項含檔案路徑、行號或段落名、具體衝突內容、建議處理方向。沒有問題的類別明確寫「無」。只檢查上述檔案，不提出無關的新建議，不修改任何檔案。"
)
```

subagent 回報問題後，向使用者提出修正方案，確認後執行。

---

## 回顧模式（--review）

三階段分析：facets 調整現有配置 → report.html 評估新增需求 → friction 趨勢評估知識累積成效。

### 前置檢查

資料抽取由兩支腳本負責，先把兩支都跑完再進階段 1：

- `python3 ~/.claude/skills/x-session-learning/scripts/review-facets.py --days N`（N 取 `--review [N]` 的值，預設見〈參數〉表）
- `python3 ~/.claude/skills/x-session-learning/scripts/review-report.py`

**以最後一行 `VERDICT:` 為準，不憑輸出看起來正常就往下走**：
- `ok` → 往下走。`review-facets.py` 印出 `NOTE: facets cover fewer days than requested` 時，在報告開頭寫明要求天數與實際涵蓋日期，照現有資料繼續
- `error` → 呼叫方式錯了（參數缺值、空值或超出範圍；指定的 `--dir` / `--report` 不存在）。照 VERDICT 的原因修正呼叫後重跑，不必轉告使用者
- `unavailable` → **中止分析，不改用手寫解析繼續**。把 `PROBLEMS:` 逐條轉告使用者，依每行開頭的標籤分流（帶 `N/M` 計數的行，`[partial]` / `[shape]` 由該計數決定；其餘行的標籤是固定的。不必再從字面推測）：
  - `[missing]` → 資料不在。請使用者先跑 `/insights`
  - `[partial]` → 少數檔案壞掉，不是格式變動。請使用者先跑 `/insights` 重新產生；重跑後仍出現，依該行 `e.g.` 列出的對象查看（可能是檔名、session id 前 8 碼或 `id:key`）
  - `[shape]` → `/insights` 改了格式。打開 report HTML 或 facets JSON，對照該行指的位置找出新結構，向使用者提出腳本的修改 diff，確認後改腳本、重跑到 `ok`
  - `[crash]` → 腳本自己的缺陷或資料損壞，讀該行的例外訊息定位，同樣先提出腳本修改 diff
  - 一行沒有標籤 → 腳本漏標，本身就是 `[shape]` 等級的缺陷，修腳本

手寫解析繞過去會讓這一輪看起來成功，而格式變動要到下一輪漏掉內容時才被發現——腳本存在就是為了讓它在第一次就失敗。

### 階段 1：Facets 分析（調整現有配置）

目標：根據跨 session friction 統計，調整**已存在**的 settings / rules / skills / agents / commands。

1. 取 `review-facets.py` 的 `FRICTION_TOTALS`（各類總數）與 `SESSIONS_DETAIL`（每個 session 的 `friction_detail` 原文）。**逐則讀 detail 依主題重新分組**——同一個 facets 類型（如 `wrong_approach`）底下常混著幾種不同問題，比對覆蓋要以主題為單位
2. 讀取現有配置：`~/.claude/settings.json`, `~/.claude/rules/**/*.md`, `~/.claude/skills/**/SKILL.md`（含 plugin）, `~/.claude/agents/`, `~/.claude/commands/*.md`
3. 比對 friction 與現有配置：
   - friction 已有 rule 覆蓋但仍重複出現 → 改寫成不靠模型自己察覺的形式（禁止一個看得見的寫法，或要求對照一個先前產出的東西），或考慮 hooks 強制。只加重語氣（加粗、MUST）不算改寫
   - friction 完全沒有覆蓋 → 加入 rules 或 settings
   - permission 問題可透過 settings.json 消除
   - 成本相關 friction（token 異常高）→ 對應到 settings 的 `effortLevel` 與 model 預設。skill frontmatter 的缺漏只列為意圖聲明層級的建議，不作為成本歸因的結論——本模式讀的 facets JSON 沒有 skill、model 或呼叫路徑欄位，無法像預設模式那樣依 `/skill` 與 Skill tool 載入拆開判斷，所以一律保守取「意圖聲明」這一側（拆分的依據見預設模式的審視維度）

此階段**不建議新增** skill/agent/command，僅調整現有項目。

### 階段 2：Report 分析（評估新增需求）

目標：從 report.html 提取 facets 沒有的結構化建議，判斷是否需要**新增** settings / rules / skills / agents / commands。

1. 取 `review-report.py` 的輸出：`ITEMS`（每條帶 copy 按鈕的建議，附所屬 section id 與按鈕複製的原文）、`KEY_PATTERN`（後續建議的校準 context）、`TOOL_ERRORS`（補充 permissions 建議）、`FRICTION_SECTION`（report 自己的 friction 診斷，對照階段 1）
2. 每一項都要列進輸出的〈Report 建議逐條對照〉，結論三選一：已採納（寫到哪）/ 已覆蓋（`file:line`）/ 不採納（理由）。**列出不等於採納**——採納仍要與階段 1 friction 相關或有 report 數據支撐；`section-horizon` 的項目只在與階段 1 前 3 名 friction 直接相關時才列為 skill/agent 候選。結論為「已採納」且屬新增的項目，同步列進〈新增建議〉
3. 新增 skill/agent 的建議**必須附 model 配置**（依預設模式 §6 表格）
4. 合併階段 1 和階段 2 的建議，產出統一報告

### 階段 3：Friction 趨勢（知識累積成效）

目標：評估已建立的 rules / skills 是否有效降低同類 friction。

1. 類型層級的前後半期次數與變化 % 取 `review-facets.py` 的 `FRICTION_TOTALS`，分界時間取 `HALF_BOUNDARY`
2. 主題層級（階段 1 重新分組的結果）由你逐則判讀前後半期——腳本只依類型加總，不做主題分組
3. 趨勢判定：

| 後半期 vs 前半期 | 判定 | 建議 |
|------------------|------|------|
| 次數明顯下降（>30%） | 配置有效 | 維持現狀 |
| 次數相近（變動 <30%） | 配置未生效 | rule → 改寫成不靠察覺的形式或加 hook 強制 |
| 次數仍高且有明確步驟可編碼 | 知識未被程序化 | rule → 升級為 skill |

### 輸出格式

```markdown
## Session Learning Review (最近 N 天)

**分析範圍**: X 個 sessions (Y 個有 facets 資料)
**Report 日期**: `review-report.py` 的 `REPORT_MTIME:`

### Friction 統計
| 類型 | 次數 | 現有覆蓋 |
|------|------|----------|
| wrong_approach | 40 | rules/core/communication.md (部分) |
...

### 現有配置調整建議（來自 Facets）
| 目標 | 修改內容 | 理由 |
|------|---------|------|
| settings.json | 加入 permissions | session 中被 reject N 次 |
| skills/xxx | 補 `model: haiku` | reference loader 未宣告 model；此為意圖聲明，非已驗證的成本控制（見預設模式的審視維度） |
...

### 使用者行為 Context（來自 Report）
> Key pattern: [從 Impressive Things You Did 的開場段提取的行為摘要]

### Report 建議逐條對照
| section id | 建議項目 | 結論 |
|------------|---------|------|
| section-features | CLAUDE.md：Device Safety | 已覆蓋 rules/x.md:NN |
| section-patterns | 先列計畫再動手 | 已採納 → rules/x.md §5 |
| section-horizon | issue → backport pipeline | 不採納：與前 3 名 friction 無直接關聯 |
...

### 新增建議（來自 Report）
| 類型 | 內容 | 建議 model | 依據 |
|------|------|-----------|------|
| skill | 新增 xxx skill | sonnet | section-features 的對應項 + 使用頻率 |
...

### Friction 趨勢
| Friction 類型 | 趨勢 | 現有覆蓋 | 建議 |
|--------------|------|----------|------|
| wrong_approach | 持平 | rules/xxx.md | 改寫 or hook |
...

### 待確認
- [ ] 調整 1: ...
- [ ] 新增 1: ...
```

`--review` 模式修改完成後，同樣**必須**執行「修改後一致性審視」（見預設模式段落）。

---

## Quick 模式（--quick）

異常時在 Token 行後補充（否則不顯示）：
- Cache hit 低於 60%：加 `Cache hit: X% — context 重用效率低，可能加速 token 消耗`
- 出現非 opus 的 turn：加 `Model: <名稱> Xk tokens — 使用者打 /skill 開的那一輪，跑在該 skill 宣告的 model 上`。反過來「有 opus turn」不是訊號，自動觸發載入的 skill 本來就都跟著 session 跑 opus
- 有 advisor 呼叫：加 `Advisor: N 次 / Xk input（全價，不吃 cache）`

```markdown
## Session Learning (Quick)

Token: Xk input / Xk output / Xk cache_read（依 `message.id` 去重後）

Top 3 問題:
1. [High] 問題 → 影響
2. ...

建議:
1. 改進方式 → 預期效果
2. ...
```

---

## 演進模式（--evolve）

對照 Claude Code release notes，找出新功能或行為變更，提案更新自身 SKILL.md 的分析維度。隨版本演進，避免分析能力落後。

**完整流程見 [evolve-workflow.md](references/evolve-workflow.md)**——Phase 1 版本基準（`.last-evolved` marker 與 `--force-from` 的優先序）、Phase 2 取得 release notes、Phase 3 過濾與本 skill 分析維度相關的 signal、Phase 4 比對自身 SKILL.md 找 gap、Phase 5 提案格式與 AskUserQuestion 選項、Phase 6 執行與更新 marker，以及該模式自己的注意事項（只改自身 SKILL.md、一致性審視照跑不設例外、優先合併而非新增）。

---

## 注意事項

- 所有模式皆需使用者確認後才執行修改
- **預設/--quick**：基於當前 session 資料，可建議新增或修改任何配置
- **--review**：階段 1-2 對照 facets 與 report.html，階段 3 評估 friction 趨勢
- **--evolve**：依 release notes 補齊自身的分析維度；流程與該模式的注意事項（含一致性審視的觸發條件）見 [evolve-workflow.md](references/evolve-workflow.md)
- 聚焦 AI 行為與成本優化，非程式碼品質
- 知識捕獲遵循最小修復原則 — 一個模式對應一個 skill/memory 建議，不發散
- --review 依賴 `/insights` 產生的 facets 和 report
- --evolve 依賴 GitHub Releases API；無網路時 fallback 至 CHANGELOG.md
- **Per-model / cache / duration 指標**：從 JSONL transcript 聚合，解析陷阱見 [transcript-parsing.md](references/transcript-parsing.md)。`~/.claude/usage-data/session-meta/` 無 model 與 cache 欄位，不能替代；skill 也無法呼叫 `/usage`（互動指令）
