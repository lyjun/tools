# Transcript Parsing Reference

解析 session JSONL 的機制與陷阱。以下每一條都對應一個已實際發生的解析錯誤，其共同性質是產生錯誤數值而非拋出錯誤，因此不會在執行時被發現。各節標有自己的量測日期；未標者量測於 2026-08-19，樣本為當時 `~/.claude/projects/` 下的 248 個 session。

## 檔案位置

```
~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
```

`<encoded-cwd>` 為 cwd 的 `/` 替換為 `-`（`/Users/x/proj` → `-Users-x-proj`）。以 python3 逐行 `json.loads`，無法解析的行略過。

per-model、cache、duration 三項指標只能由此檔計算：`~/.claude/usage-data/session-meta/` 不含 model 與 cache 欄位，而 `/usage` 是互動指令，skill 無法呼叫。

## 陷阱一：`usage` 重複 emit，未去重會使總量倍增

streaming 將同一則 assistant message 的 `usage` 在多行重複寫出，內容完全相同，單一 id 觀測到最多 5 次。逐行加總會將同一筆 token 重複計入。

正確做法是先按 `message.id` 分組，每個 id 只取一份 usage，再依 `message.model` 加總四種 token。同一 session 兩種算法的差距：

| 指標 | 逐行加總 | 依 id 去重 | 比值 |
|---|---|---|---|
| assistant turns | 350 | 164 | 2.13 |
| output tokens | 335,621 | 150,081 | 2.24 |
| cache_read | 71,053,937 | 31,893,369 | 2.23 |

cache hit 為比值，兩種算法的差距在 0.2 個百分點以內，因此該指標正常不足以佐證 token 總量正確。

## 陷阱二：tool call 的去重鍵是 `(message.id, block.id)`

本節有兩條規則——去重鍵，以及 message 順序表的建法。缺任一條都會讓 tool call 數失真，換對了鍵不等於這一節就過了。

同一則 API message 內的多個 `tool_use` block 分散在不同 JSONL record。逐行計數會將每個平行呼叫視為獨立一批，平行化比例恆為 0%。

分組後計算每組大小：`{1: N}` 表示全部為單發，`{1: a, 2: b, 3: c}` 才能反映平行化程度。

**去重鍵是 `(message.id, block.id)`。** 只按 `message.id` 分組不夠——同一個 block 會隨 record 重複出現，逐筆 append 到該 mid 的清單會把它算兩次。

**message 的順序表要用自己的 `seen` 集合去重，不能用「blocks 裡有沒有這個 mid」代替。** 一則 message 的第一筆 record 可能只帶文字 block，`blocks[mid]` 因此還沒被建立，於是同一個 mid 在後續 record 又被加進順序表一次，接著整批 block 被算兩遍。

三個數字量測於同一個 session（2026-08-24），差異全部來自上述兩個鍵：

| 算法 | tool call 總數 |
|---|---|
| 只按 `message.id` 分組，未對 block 去重 | 221 |
| 加了 block 去重，但順序表用 `mid not in blocks` 判斷 | 467 |
| 兩個鍵都正確 | 225 |

第二列是最危險的一種：它是「修好陷阱二之後」的版本，數值反而比錯的版本更離譜，而且兩次都不會拋錯。產出報告前對帳（分項加總 == 總數）能抓到不一致，但抓不到這一種——兩個數字同源，會一起錯。

## 陷阱三：使用者訊息分布在兩種 record

`type=user` 僅涵蓋輪次邊界送達的訊息。mid-turn 送出的訊息（隨 tool result 一併呈現者）不產生 `type=user` record，僅存在於 `queue-operation`。一個 session 的四次推翻中有三次屬於後者，只掃 `type=user` 會全部遺漏。

取兩個來源的聯集：

| 來源 | 條件 | 條件的作用 |
|---|---|---|
| `type=user` | `isMeta` 不為真，且 `message.content` 為字串 | 此型別同時承載三種內容：`isMeta: true` 為 skill 載入的內容，`content` 為 block list 者為 tool_result。兩者都會整組命中訊號詞，造成虛報 |
| `type=queue-operation` | `operation == "enqueue"` 的 `content` | 同一則訊息另會 emit `remove` 與 `popAll`；全部 session 中 `enqueue` 均為內容的超集，限定此值可避免重複計入 |

聯集後依內容去重，並排除開頭為 `<` 的項目（`<task-notification>` 等系統記錄）。同一 session 的實測：只掃 `type=user` 得 21 筆，聯集後 26 筆。

## 陷阱四：`usage` 不含 context window 佔用

`usage` 的欄位為 `input_tokens`、`output_tokens`、`cache_creation_input_tokens`、`cache_read_input_tokens`、`cache_creation`、`iterations`、`output_tokens_details`、`server_tool_use`、`service_tier`、`speed`、`inference_geo`，其中無任何欄位表示 context window 的佔用或上限。

累計的 `cache_read` 會遠超過 window 容量（實測 32M 對 1M window），因此據以計算的百分比不具意義。報告只列實際可得的 token 量，不寫 `X / Total (Y%)`。

## 陷阱五：advisor 的 token 不在頂層 `usage`

頂層 `usage` 的四種 token 只等於 `usage.iterations[]` 中 `type == "message"` 那幾項的加總。advisor 的呼叫另成 `type == "advisor_message"` 的項目，帶自己的 `model`，不計入頂層。只加總頂層，advisor 的成本整筆消失，而且不會出錯。

量測於 2026-10-11，全部 session 中含 advisor 的訊息依 `message.id` 去重後 205 則：頂層四欄位等於 `message` 項目加總者 205、不等者 0。advisor 項目共 205 個（每則恰 1 個）：

| advisor model | input | output | cache_read | cache_create |
|---|---|---|---|---|
| `claude-opus-5` | 24,146,326 | 744,966 | 0 | 0 |
| `claude-opus-5-5` | 14,694,578 | 586,558 | 0 | 0 |

cache 兩欄恆為 0，每次呼叫的 input 都是全價。因此 advisor 另列一行，不併進 session model 的分布，也不放進 cache 效率的分母——放進去會把 cache hit 拉低，而那不是主對話的 context 重用問題。advisor 的呼叫次數取 `type == "advisor_message"` 的項目數，不取 `server_tool_use` block 的出現次數：後者隨 record 重複出現，未去重時會多算。

## assistant record 的其他欄位

`message` 之外的頂層欄位：

| 欄位 | 內容 | 用途 |
|---|---|---|
| `attributionSkill` | 該 turn 歸屬的 skill 名稱 | per-skill turn 數，即 skill 的成本歸因基準。`Skill` tool_use 的次數只反映觸發頻率，不含該次觸發之後延續的 turn |
| `effort` | 該 turn 實際採用的 effort | 對照 skill frontmatter 的 `effort:` 是否生效 |
| `isSidechain` | subagent turn 標記 | 全部 session 中為 0 筆，subagent 的 turn 不寫入此類檔案。任何關於 subagent 行為的結論都無法由本資料源得出 |
| `advisorModel` | advisor 使用的 model | 成本以 `usage.iterations[]` 的 advisor 項目為準，見陷阱五 |
| `requestId` / `version` / `gitBranch` | — | — |

## 量測：frontmatter 的 model 與 effort 是否生效

兩個互補算法，結論一致。

**算法一，整段歸屬**：`attributionSkill` 交叉 `message.model`。17 支 skill、約 12000 個 attributed turn，全部為 opus 變體。三個代表性案例：

| skill | frontmatter | 實際 turn |
|---|---|---|
| `x-environments` | `model: haiku` | 2754 turn，全部 opus |
| `x-worktree` | `model: haiku` | 1908 turn，全部 opus |
| `arx-pr-pre-flight` | `model: sonnet` | 646 turn，全部 opus |

**算法二，僅取緊接一輪**：用於排除「override 僅持續一輪」的解釋，取每次 `Skill` tool_use 之後的第一個 assistant turn。685 次呼叫中，opus 674 次、`<synthetic>` 11 次，haiku 與 sonnet 均為 0。

effort 的情況相同：量測當時 `arx-cluster-ops` 宣告 `effort: normal`，實際 turn 為 xhigh 417、high 130，即繼承 session 的 effortLevel。注意這個樣本已無法再現——`normal` 經官方文件確認不是合法值，該檔已於 2026-08-24 改為 `effort: medium`，所以上面的數字量到的是「無效值被靜默忽略」，而不是「有效值不生效」。要複驗 effort 這半必須拿宣告有效值的 skill 重測；2026-08-24 在 v2.1.241 上的定向實測（`effort: xhigh` 的 skill 在 `--effort low` 的 session 下回報 `xhigh`）得到相反結論。

結論（2026-08-19 版，已於 2026-09-06 修正，見下段）：inline 呼叫的 skill，frontmatter 的 `model:` 不改變該 turn 實際服務的 model。**這個結論只涵蓋 `model:`**——effort 那半的狀態是未解（理由見上一段：舊樣本量到的是無效值被忽略，而 v2.1.241 的定向實測結論相反），判準住在 `x-cc-config-guide`〈Effort 限制〉，不要從這裡讀出 effort 的結論。此結論不改變「是否應設 `model:`」的答案——設定值仍是意圖聲明，並在機制修復後成為生效條件——但改變成本判讀：per-model 分布無法指認哪一支 skill 在高成本 model 上執行，因為所有 turn 的 model 相同。（此結論已於 2026-09-06 依呼叫路徑拆分，見下段複驗。）

**複驗（2026-09-06，v2.1.263）：上面的結論要按呼叫路徑拆成兩半，其中一半已被推翻。** 重跑時在原演算法上多取兩個維度——記錄自身的 `version` 欄，以及該 skill 在那個 session 是以 `<command-name>` 出現（使用者打 `/skill`）還是以 `Skill` tool_use 出現（模型中途載入）：

- **使用者打 `/skill` 開一整輪：現在會生效，舊結論在這一半已被推翻。** `x-session-learning`（宣告 sonnet）與 `x-cc-release-cfg-sync`（宣告 sonnet）在 v2.1.223 / 2.1.235 / 2.1.241 / 2.1.251 的 5 個 session 全跑 `claude-opus-5`；到 v2.1.261（97 turn）與 v2.1.263（50 turn）全跑 `claude-sonnet-5`
- **模型中途用 Skill tool 載入：仍不生效，舊結論在這一半維持成立。** v2.1.252 / 2.1.259 / 2.1.261 約 100 個 (session, skill) 組合，宣告 haiku 或 sonnet 者無一例外跑 `claude-opus-5`
- **同版控制組**：v2.1.261 同時有 slash 的 `x-session-learning`（sonnet→sonnet）與 tool 載入的 `x-environments`（haiku→opus）。區分因素是呼叫路徑，不是版本

對成本判讀的影響：per-model 分布仍然無法指認**自動觸發的** skill 跑在哪個 model 上（那些 turn 的 model 一律等同 session），但 slash 開起來的那一輪現在可以，非 opus 的 turn 就是它。effort 那半不在這次複驗範圍內，維持未解。

複驗方式：重跑上述演算法，並且**務必分開 slash 與 tool 兩條路徑**——不分路徑會像 2026-08-19 那樣把兩個不同的結果混成一個結論。
