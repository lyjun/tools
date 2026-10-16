---
name: x-cc-config-guide
description: "Considerations checklist before modifying Claude's meta-configuration. Trigger when: creating or modifying any ~/.claude/skills/*/SKILL.md (frontmatter, description, or content), adding or restructuring files in ~/.claude/rules/, deciding what to write into MEMORY.md, evaluating whether to enable a plugin, judging whether a piece of knowledge should be a rule, skill, or memory entry, or deciding whether a procedure written as SKILL.md prose should become a script under a skill's scripts/. Provides per-domain notes to avoid common mistakes."
model: sonnet
---

# Claude Config Guide

修改 Claude 的 meta-configuration 前的 considerations。依當前任務讀對應段落即可；各節大致獨立，例外是 §1 的〈何時把散文轉成 script〉與 §6 的 YAGNI 互為條件，只有這兩節互相標了對方；§6 另外單向指向〈什麼不該轉〉。

---

## 1. Skill 設計與配置

### Model 選擇

| 任務性質 | model |
|---------|-------|
| Orchestration（git 指令、檔案偵測、流程控制） | `haiku` |
| Reference loader、簡單摘要、格式化 | `haiku` |
| 推理、寫作、跨檔分析 | `sonnet` |
| 深度 reasoning（必要時） | `opus`，frontmatter 注解原因 |

### Lock model 強制

所有新建 skill 在 frontmatter 設 `model:`，即使預期用 sonnet 也明示 `model: sonnet`。

要理解這條要求目前的效力，先看版本、再看呼叫路徑（2026-09-06 在 v2.1.263 上複驗，量測見「Skill model 與 effort 的實際效力」）。**第一個觀察到生效的版本是 v2.1.261**；在那之前兩條路都不生效，所以在更舊的 CC 上下面這個分岔不成立：

- **使用者打 `/skill` 開一整輪 → `model:` 真的生效**，該輪跑在宣告的 model 上
- **模型在回合中途用 Skill tool 載入 → 不生效**，整輪維持 session 的 model

要注意這是**該次呼叫**的屬性，不是某支 skill 的屬性：同一支 skill 兩條路都會走，`/x-worktree` 打進去那輪生效，同一支被 description 自動觸發時就不生效。所以省到的是「以 `/skill` 開頭的那些輪次」，不是「某幾支 skill」——這也是為什麼**每一支都該設 `model:`**，而不是只設會被打成指令的那幾支。對自動觸發的那些輪次，這個值仍只是意圖聲明（讓讀 skill 的人知道該用什麼等級），不要當成已完成的成本控制。

### Description 撰寫

`description` 是 main agent 路由的**唯一依據**——寫不好就不會觸發或誤觸。

**好的 description 同時包含**：

- **做什麼**：skill 的功能（一句話）
- **何時觸發**：具體情境，最好用「Trigger when: ...」列舉
- **邊界**：暗示什麼情境**不該**用（不必明寫，但範圍要清楚）

**注意點**：

- 略微 pushy——agent 預設傾向 undertrigger，描述太客氣就漏觸發
- 避免通用詞（"helper"、"tool"、"manage"）——區分性差
- **不要提其他 skill 名稱**（破壞解耦，見下）
- 簡單一步任務（如「讀檔案」）不會觸發 skill，無論 description 多精確——因 agent 直接用基本工具處理

**校準方法**：建立後可用 trigger eval 工具做精準度測試——準備一組 should-trigger / should-not-trigger 的查詢樣本，跑過去看實際觸發率。生態系內若有現成的 description optimizer 就用它。本機用 `scripts/routing-eval/run.py`：eval 沙箱會封住 HOME，個人 skill 與 rules 不會自己載入，這支把兩者組成臨時 plugin 再跑；最後一行 `VERDICT: unavailable` 代表沒量到東西，不是通過。改 description 前後各跑一次，`--runs 3` 以上才拿來比。

### 解耦合（Decoupling）

每個 skill 是獨立單位，main agent 看 description 決定該用哪個。SKILL.md 內**不該認識其他 skill**。

**禁止 routing pattern**：

- 不要寫「不在我範圍時請去用 X skill」、「該情境改用 Y skill」這類引導
- 不要在自己的 description 提其他 skill 名稱（如「Does NOT cover settings.json (use update-config)」這種寫法）
- 不要為了「導流」而設計 router skill

理由：
- 範圍判斷是 main agent 看各自 description 的工作，不是 skill 內容的工作
- 內部 routing 讓 skill 互相耦合，改名/刪除會牽動多檔
- 帶 routing 文字時，agent 可能直接跳去 X skill，繞過原本判斷

**允許 composition pattern**：skill workflow 中作為步驟呼叫另一個 skill（如 `x-code-review` 在 review 過程中 invoke `x-coding-standards` 載入語言規範）。這是「把 X 當工具用」，不是「請使用者轉去 X」。差異在意圖：composition 是自身工作流的一部分，routing 是把責任推給別的 skill。

**範圍重疊處理**：

- 兩個 skill description 太相近會誤觸 → 修改 description 加區分性關鍵字
- 真重疊嚴重 → 合併或刪除其中一個，不要互相 reference

### Effort 限制

- 合法值：`low / medium / high / xhigh / max`。官方文件（code.claude.com/docs/en/skills 的 frontmatter 參考表）列這五個並註明「available levels depend on the model」。「haiku 不支援 effort」只對 Haiku 4.5 成立；Claude Haiku 5.5 在 API 上支援全部五級（預設 `medium`），經 skill frontmatter 是否傳遞未複驗
- **主 session 內呼叫時 `effort:` 是否生效，目前是未解的衝突**——本機 2026-08-19 的量測說不生效（見「Skill model 與 effort 的實際效力」），但 2026-08-24 在 v2.1.241 上的定向實測說生效：`effort: xhigh` 的 skill 在 `--effort low` 的 session 下於主 session 內呼叫回報 `xhigh`，加了 `context: fork` 也是 `xhigh`。兩者差 5 天且跨版本，可能是機制已修。要據此做成本判斷前先重跑量測，不要挑一邊當定論
- **這條衝突只涵蓋 `effort:`。** 08-24 那次定向實測測的是 effort。`model:` 那半已於 2026-09-06 在 v2.1.263 上複驗結案（見〈Skill model 與 effort 的實際效力〉）：分呼叫路徑，`/skill` 生效、Skill tool 中途載入不生效。effort 這半沒有對應的複驗，本節的衝突維持未解——不要拿 model 的結論外推到 effort，兩者是分開量的。另外 08-24 那次定向實測**沒有記錄呼叫路徑**，而路徑分裂本身就是這個衝突的候選解釋之一，所以 effort 的任何複驗都必須把 `/skill` 與 Skill tool 中途載入分開量，否則會像 08-19 那樣把兩個不同結果混成一個結論
- 合法值分歧已於 2026-08-24 結案：先前記錄的「現存 skill 用 `normal`」指的是 `arx-cluster-ops`，`normal` 經官方文件確認不在合法值內，該檔已改為 `effort: medium`。無效值的處置無文件，實測是靜默忽略、退回 session 的 `effortLevel`。第一方參照：`plugins/.../claude-security/agents/` 用 `medium` 與 `xhigh`，無任何第一方檔案用 `normal`

### Orchestrate + Subagent 分層

複雜 skill 採 haiku orchestrate + sonnet subagent 的 pattern：

- skill frontmatter `model: haiku`
- workflow 中明示 `Agent(subagent_type=..., model: sonnet, ...)` 做重 task
- 範例：`x-code-review`、`x-code-improvement`

理由：orchestration（branch 偵測、檔案 list、流程決策）不需要高階推理能力，分析才需要。

上面兩個半邊的效力不同，分開看：

- **`Agent(model: ...)` 這半可照上面寫，它是獨立機制。唯一例外是把 `model` 當工具參數傳給 `subagent_type: "fork"`**——那裡它被靜默丟棄、沒有錯誤也沒有提示，仍以呼叫端的 model 計費。要便宜的 subagent 就改開一支新 agent 明示 model，代價是 fork 本來免費繼承的 context 要重新交代一次
- 上一點只管**工具參數**。skill 以 `context: fork` frontmatter 搭配 `model:` 是另一個機制，依 `~/.claude/rules/tool-constraints.md`〈Agent: A `fork` Subagent Ignores the `model` Parameter〉那條路會生效——但**那節對這半只有斷言、沒有實測數據**，引用時只能引「兩者是不同機制」這個分界，不能當成已量測的結論
- **skill frontmatter `model:` 這半要看呼叫路徑**（依〈Skill model 與 effort 的實際效力〉2026-09-06 的複驗）：本 workspace 的 skill 沒有一支用 `context: fork`，全走主 session 內那兩條路。被 description 自動觸發、由模型在回合中途用 Skill tool 載入的**不生效**；使用者打 `/skill` 開一整輪的才生效
- 所以 **「orchestrator 標成 haiku」在被自動觸發的那些輪次不是成本控制**（`x-code-review`、`x-code-improvement` 這兩個範例被自動觸發時就屬於這種），被打成 `/x-code-review` 的那輪才省得到。不分路徑都確定省得到的，仍只有 subagent 的 model 指定
- 反過來說，**workflow 裡的 `Agent` 沒指定 model 才是真正會漏掉的成本**——它會繼承呼叫端的 model

### Skill model 與 effort 的實際效力

分三條呼叫路徑，結論不同：使用者打 `/skill`、模型在回合中途用 Skill tool 載入、在 subagent 內。前兩條都在主 session 裡，第三條無資料。

**主 session 內（前兩條）：2026-09-06 在 v2.1.263 上複驗結案，兩條路的結論相反。** 演算法同下（`attributionSkill` 交叉 `message.model`），另外多取兩個維度：記錄自身的 `version` 欄，以及該 skill 在那個 session 是以 `<command-name>` 出現（使用者打 `/skill`）還是以 `Skill` tool_use 出現（模型中途載入）。只看宣告 haiku/sonnet 的 skill，因為 session 基底是 opus，宣告 opus 的樣本無法區分：

- **`/skill` 打進去的：修復前後可直接對照。** 同樣兩支 skill（`x-session-learning` 宣告 sonnet、`x-cc-release-cfg-sync` 宣告 sonnet），v2.1.223 / 2.1.235 / 2.1.241 / 2.1.251 共 5 個 session 全跑 `claude-opus-5`；v2.1.261（97 turn）與 v2.1.263（50 turn）全跑 `claude-sonnet-5`。這兩支是這台機器上僅有的 slash 樣本
- **模型中途用 Skill tool 載入的：修復後仍不生效。** v2.1.252 / 2.1.259 / 2.1.261 約 100 個 (session, skill) 組合，宣告 haiku 或 sonnet 者無一例外跑 `claude-opus-5`
- **同版控制組**：v2.1.261 同時有 slash 的 `x-session-learning`（sonnet→sonnet）與 tool 載入的 `x-environments`（haiku→opus）。同一版、不同路徑、不同結果，所以區分因素是呼叫路徑，不是版本
- 修復落在哪一版無法從本機資料再收斂：最後一個壞掉的 slash 樣本是 v2.1.251，第一個好的是 v2.1.261，中間沒有 slash 樣本。release note 把它記在 v2.1.259

下面是 2026-08-19 的原始量測，樣本為當時 `~/.claude/projects/` 下的 248 個 session。它沒有區分呼叫路徑，而當時 slash 與 tool 兩條路都不生效，所以結論與上面的第一、二點都不衝突：

- 取 assistant record 的 `attributionSkill` 交叉 `message.model`，17 支 skill、約 12000 個 attributed turn 全為 opus 變體。`x-environments` 宣告 `model: haiku`，2754 個 turn 全 opus；`arx-pr-pre-flight` 宣告 `model: sonnet`，646 個 turn 全 opus
- 為排除「override 僅持續一輪」的可能，另取每次 `Skill` tool_use 之後的第一個 assistant turn：685 次呼叫中 opus 674、`<synthetic>` 11，haiku 與 sonnet 均為 0
- effort 同樣：當時唯一設了 effort 的 skill（`arx-cluster-ops`，宣告的是已知無效的 `effort: normal`）實際跑的是 session 的 `effortLevel`。該檔已於 2026-08-24 改為 `effort: medium`，所以這一列的原始樣本無法再現；要複驗 effort 這半，需要拿一個宣告**有效**值的 skill 重新量測，而 2026-08-24 的定向實測在 v2.1.241 上得到相反結果（見「Effort 限制」）

**subagent 內呼叫：無資料，不要當作已知行為。** 上述樣本中 `isSidechain: true` 的 record 為 0 筆，subagent 的 turn 不寫入 session transcript，因此「skill 在 subagent 內是否 override 該 turn」無法由這個資料源判定。上面「Orchestrate + Subagent 分層」用的是 `Agent(model: ...)` 這個獨立機制，不受本節結論影響。

實務影響，**僅限 Skill tool 中途載入那條路**（`/skill` 那條已於 v2.1.261 起生效，不適用下面這段）：純 file loader 設 haiku 不會降級（因為根本沒切換），含分析邏輯的 skill 設低 model 也不會降級——兩種舊有的判斷都建立在 override 真的發生。要重新確認這條路的機制時重跑上面兩個算法；**tool 載入路徑**出現非 opus 的 turn 才表示已變更。注意這個判準不能拿去掃全部 turn：`/skill` 開起來的那些輪次現在本來就會出現 sonnet 或 haiku，那是預期內的，不是機制又變了。

### SKILL.md 規模

控制在 **500 行內**，超過就拆 `references/` 子目錄做 progressive disclosure：

- **Metadata**（name + description）：永遠在 context（~100 字內）
- **SKILL.md body**：觸發時載入（< 500 行理想）
- **`references/`**：按需讀取（無上限）
- **`scripts/`**：可執行的程式碼，不需載入 context；同時是把**非決定性步驟**移出散文的地方（見下面三節）

多 domain 變體（如 `cloud-deploy/` 含 aws/gcp/azure）拆 `references/<variant>.md`，SKILL.md 只放選擇邏輯。Claude 只讀對應的 reference 檔。

### 何時把散文轉成 script

判準兩個條件都要：**這段散文已經在用**，而且**同一份輸入照它走兩次會得到不同結果**。前者把 §6 的一次性任務擋在外面（那節說「一次性任務：直接做，不寫」），後者把決定性的重複擋在外面——「看起來重複」當判準才會跟 §6 打架。

決定性是**理由**，不是檢查方式：問自己「這段將來會不會跑出不同結果」是要求 agent 預測自己未來的行為，照〈寫作語氣〉的排序這是最弱的那一型。下手時看的是三個看得見的形狀：

- **SKILL.md 裡的 inline 指令帶佔位符**——`__RANGE__`、`<repo path>` 這類要 agent 當場填的。grep 得到，不必先察覺什麼。填錯不會報錯：填空字串進 `git -C` 就是在錯的目錄跑，而輸出仍然像成功。實例是 `x-code-review/scripts/range-detect.sh` 取代掉的那段 inline bash——它在整份 SKILL.md 只出現一次，卻是最該轉的，這就是為什麼判準不是重複次數
- **一份清單在 script 之外還有第二份**——搬成執行時去讀單一來源
- **多步驟且每步是固定指令**，步與步之間只有資料流沒有判斷

第二個形狀有一條分界，弄反了會製造出你正要消滅的那第二份真相：**看那個值是 script 消費，還是讀輸出的人消費。** script 消費的（一份檔名排除清單）→ 執行時去讀來源。人消費的（一條 review 深度的邊界數字）→ 只能稱名、永不重述，搬進 script 反而多一份會漂的副本。`x-pr-review/scripts/pr-size.sh` 同時是這兩半的實例：它執行時去讀 `x-coding-standards` 的排除清單，同時拒絕說出量到的數字屬於哪一級。

轉完要把被取代的散文刪掉——留著的話 agent 讀到的是散文，script 等於沒寫，這是最容易發生的半成品狀態（§6：寫一半放著比沒寫更糟）。**檢查方式不是「記得刪」**：加完 `scripts/x.sh` 之後，拿 x.sh 裡實際跑的那幾個指令去 grep 這份 SKILL.md，有命中就是殘留。

### 什麼不該轉

**下手前先把 input → output 表寫出來**：會接受的每一種輸入一列，正確輸出一列。填不滿的那幾列就是該留在散文的部分——某個輸入上兩個夠格的人會給不同答案，那一列就填不出來。要求先產出這張表而不是問「我寫不寫得出來」，是因為後者憑想像就能回答 yes，而表格填不滿是看得見的。

填得滿的例子：「這個 range 改了哪些檔」、「這個 SHA 還在不在」、「這個路徑是否命中這條 ERE」、「這個 ref 是不是 commit」。填不滿的：severity 定級、一則 finding 值不值得提、design trade-off 的取捨——把這些寫成 script 只是把判斷藏進一段沒人審的程式。

第二條界線：**script 可以量，不可以判。** 檢查方式是看輸出裡有沒有「接下來該怎麼做」的結論。兩種不算違反：量測成功與否的 `VERDICT:`；以及**用固定規則從它自己已經印出的欄位推出來的結論**——`pr-state.py` 印一個 `FROZEN:`（狀態不是 OPEN，或 head 沒動且沒人回覆）算量測，因為讀者拿同樣那幾個欄位會推出同樣的答案；同一支拒絕給「這輪走哪個 case」的標籤，因為那個要判斷。分界在讀者能不能從印出來的欄位重算出同一個答案，不在它長不長得像結論。

### script 的失效形狀

rule 的失效是「沒察覺」，script 的失效是 **exit 0 而什麼都沒量到**。它更難發現，因為呼叫端拿到的是一份看起來正常的輸出，沒有任何一處提示它是假的。

三個 verdict 就夠，取名一致：`ok` / `error`（用法或輸入錯）/ `unavailable`（跑了，但沒讀到該讀的東西）。

- **每一條 exit 路徑都印一行 in-band `VERDICT:`**，exit code 與它對應；多目標時每個目標一段、最後一行總結。是「每一條路徑」不是「至少一行」——漏掉的那條正是最需要它的那條（`set -u` 撞到未設變數會在印任何東西之前就死掉）。Bash tool 的狀態列看不出 script 中途某個指令失敗，所以呼叫端契約一律讀 VERDICT 那行
- **「殘缺地成功」有自己的 verdict，就是 `unavailable`**——跑完了但 submodule 是空目錄、清單抽不到、range 有一側解析不出來，都不能報 ok；報 ok 的那一刻，呼叫端就沒有第二次機會發現
- **測 exit code 是必要但不夠**。壞 ref 的 `git diff` 是 exit 128 加空 stdout（抓得到），但空左側的 `git diff --name-only "...HEAD"` 是 **exit 0、stdout 空、stderr 也空**，git 把缺掉的左側代換成 HEAD。這一類只能在呼叫外部指令**之前**用結構檢查擋掉（範圍必須有三個點、兩側都不得為空），事後看回傳值看不出來。同理不要用「輸出是空的」判斷成功：`tar` 對空輸入是成功的
- **守衛用的 grep 有三支結果**：match（0）/ nomatch（1）/ **拒絕這個 pattern**（2）。把 2 併進 nomatch 那支，壞掉的 pattern 會被診斷成「範圍太窄」——症狀為真而指向錯的原因，讀者會去改清單內容。**不要靠 `||` / `&&` 的接法來 fail closed**：那取決於守衛的極性而不是運算子。「這個字串必須存在」接 `||`，撞到 2 會觸發；「這個字串必須不存在」寫成 `! grep -q` 或接 `&&`，撞到 2 會被判定為乾淨而靜默放行——而後者才是實務上更常寫的那個極性。顯式分三支：`grep -q …; case $? in 0) …;; 1) …;; *) …;; esac`
- **一個抽樣探針蓋不住一份清單**。用單一樣本驗一條十幾個 arm 的 pattern，過寬的改動只要沒碰到那個樣本就照樣通過。探針取自那份清單自己列出的「必須保住」項目，而且要多個；來源沒列出那種項目的話，先去那邊列——否則這條規則沒有比對物件，會靜默失效
- **成功路徑也要印出它實際讀到的值**。只印來源（「讀自某檔」）而不印內容，一個通過探針但仍然錯的值就在輸出裡留不下任何痕跡

**放哪裡**：擁有那道關卡的 skill 的 `scripts/` 底下。`~/.claude/scripts/` 不是標準位置。別的 skill 要用就以絕對路徑 `~/.claude/skills/<skill>/scripts/<name>.sh` 呼叫，並在呼叫端寫明它屬於誰——這是 composition 不是 routing（見〈解耦合〉）。呼叫一律用絕對路徑：agent 的 cwd 是任意的，相對路徑跟上面那個填空的 `git -C` 是同一類失敗，只是高一層。

**語言**：要處理 map 或 JSON 就寫 Python。`#!/usr/bin/env bash` 在這台機器上是 3.2，沒有 associative array。

**驗收**（對照〈寫作語氣〉那條「套回觸發它的那個實例」）：每個旗標各跑一次缺值、一次空值，再跑一次壞輸入，看它是報錯還是靜默。缺值那次會撞到 `shift 2` 在只剩一個參數時回 1 且不 shift——bash 與 sh 都如此且不出聲（zsh 會印一行），於是參數迴圈無輸出地空轉。空值是另一半：被當成沒給的旗標會讓 script 靜默改走預設路徑，然後對一個呼叫端從未指名的目標回報 ok。這台機器沒有 `timeout`，所以缺值那一項要自己包背景執行加 kill，否則真的空轉時會卡住整個呼叫。

### 寫作語氣

- 用**祈使語氣**（imperative form）
- 解釋**為什麼**，不只列**是什麼**——LLM 有 theory of mind，理解 why 比照單全收 MUST 更穩
- **避免堆砌 ALWAYS / NEVER / MUST**：是 yellow flag，改用解釋讓 agent 自己推理
- **寫完把規則套回觸發它的那個實例，寫出它在哪一步擋下來**——寫不出那一步，這條就是無效的。規則失效最常見的原因不是內容寫錯，是它依賴 agent 先「察覺」某件事，而沒察覺往往正是原本出錯的那個環節。三種形狀命中率遞增：
  - **警覺型**（「用到 X 時記得檢查 Y」）：最弱，等於用當初失效的自我監控去檢查自己
  - **替換型**（「不准寫 X，要改寫成 Y」）：禁止一個看得見的寫法，打完字就知道違規
  - **對照物件型**（「這個主張必須對得上先前產出的 Z」）：最強，yes/no 檢查不需要先察覺什麼；但要確認 Z 在流程裡被保證產出，否則規則靜默失效
- **套回實例時拿原文，試著照新規則把它改寫成合規**：寫得出來，就是沒擋下。用自己的轉述去套，出錯的那一步會被寫成已經擋下。這對應 x-user-rules §6「寫出『反例長什麼樣』並實跑一次」；改寫原文是靜態的那一半，實跑的那一半見下一條（只限因實際失敗而寫的規則）。別的 model（含 advisor）確認過，不能代替這一步
- **因實際失敗而寫的規則，寫之前先跑對照組**：用觸發實例的情境（它當時所在的完整 skill 或 prompt，加一個會誘發那個失敗的任務），在**不加**新規則的情況下讓全新的 agent 各跑一次，至少 5 次。對照組一次都沒重現那個失敗，就沒有東西要修——不寫，回報使用者「對照組 N 次未重現」。重現了，再用加了新規則的版本跑，兩邊的失敗次數並列交給使用者。加了規則那邊的次數 M 要滿足「對照組失敗率 × M ≥ 3」，不到就加跑加了規則那邊——對照組 1/5 時要跑 15 次；不然加了規則的 0 次失敗和沒加時分不出來。標出的命中要逐則讀：樣板的回聲、引用的反例常被算成命中，只看自動計數會同時高估失敗與成效。預防性新增沒有既存失效可重現，不跑這條，照下面三關裡的預防性分支走；有觸發實例原文（transcript 段落、當下的輸出）的，一律不算預防性；只有使用者原話、沒有那兩樣的，仍算預防性
- **改 skill 或 rule 的規範，寫入前由一支全新的 agent 跑改寫測試**：作者先照〈套回實例時拿原文〉那條自己改寫一次，新 agent 的審查加在那之後，不代替那一步。advisor、fork、續問先前那支 agent 都看得到先前脈絡，不算。brief 給寫入後的全文與觸發實例原文（transcript 段落、使用者原話、當下的輸出），**逐字貼，不轉述**——轉述會把作者的推論寫成事實，審查者再拿它當「發生過」的依據；不給前幾輪的結論（〈跨輪編號〉的 ledger 除外）。審完又改過，就再審一次（範圍見下面〈複審範圍〉）。第一輪送出前，從觸發實例原文與使用者原話寫出「要防的事」清單，之後每輪 brief 原封不動帶同一份；審查者提出清單外的事，只能列為 follow-up，要不要擴大範圍由使用者決定。交 diff 給使用者時附上審查結論
- **寫入前的改寫測試找到的漏洞，每一則要過三關才算**，前兩關不過就丟掉，不降成「較輕的、先記下來」留著——降級正是推測留下來的路。這三關只用在寫入前的改寫測試；寫入後找重複、矛盾、遺漏的一致性審視不套這三關，那類發現本來就沒有「發生過」的時間點：
  1. **發生過**：引觸發實例原文裡這件事真的發生的時間點與原句。只寫得出「主 agent 可以把 X 說成 Y」、原文裡沒有人這樣做過的，是推測。引的原句要是這則漏洞走的**同一條路徑**上的動作，只有結果相同不算（例：原文是主線自己 SSH，漏洞走的是派 subagent 去 SSH）。作者收下每則漏洞前，自己拿原文核對這一關，不採信審查者的判定。沒有既存失效（預防性新增）時，改引使用者描述的情境原句，指出那一步在情境裡會出現
  2. **重現原失效**：照那個時間點往下走，說出重現的是哪一個原失效（例如「審完又改過、沒再審的那一版被寫入」）。只是「條文不夠嚴謹」「可以寫得更清楚」，不算。預防性新增時沒有原失效，改說出使用者情境裡要防的那件事（例如「改了 description 卻沒 grep routing.md」）照新文字仍會發生
  3. **一句修法**：指出改哪一句、改成什麼。寫不出只改一句的修法，要改的是方向，這則不丟，停下來交給使用者

  **分級與寫入條件**：三關都過、而且走的是原文實際走過的路徑 → blocking，修掉後換一支新的 agent 再審。這次修改本身是預防性新增（沒有既存失效，第一關改引使用者情境原句）、或落在「要防的事」清單外的 → follow-up，不修，寫入時連同一句修法列給使用者。單則漏洞在原文找不到同一條路徑，照第一關丟掉，不進 follow-up。blocking 為 0 就寫入。

  **跨輪編號**：漏洞從第一輪起編號（G1、G2…），每輪 brief 附 ledger：已修的編號，以及被換掉的原句與換上的原句（逐字）、已丟的編號與理由，請審查者先確認已修的沒有回歸。編號不回收。

  **複審範圍**：修補後的複審照樣給全文，但審查範圍限上一個審過的版本到現在的 diff 加 ledger 回歸檢查；整條換寫法時才全文重審。

  **換方向**：連續兩輪都有 blocking 過關，停下來交給使用者，問要不要從「靠模型察覺」改成「要求產出可核對的東西」，不再一句一句補。follow-up 不計入。

  以一次改 x-plan 的審查為例：「原文裡使用者說『改』之後，主 agent 把審完又改過、沒再審的那一版寫入」三關都過；「主 agent 可以用 fork 開新 agent，把前幾輪結論帶進去」，那次的原文裡從沒用過 fork，第一關就丟。把審查者當成鑽字眼的對手、不設這三關，每一版都找得到新的推測，規則只會越補越長
- **寫入時只套審過的 diff，不把測試用的副本整份蓋回去**：替換用的舊字串與新字串只取自交給使用者看過的那份 diff，不從「當下檔案對副本」的 diff 推出——那份會把別人寫進去的行算成要刪的行。改用 Edit，或寫一支 script 先確認每個舊字串在當下的檔案裡恰好出現一次再替換。`~/.claude` 不在 git 底下，從副本建立到寫入的這段時間，其他 session 寫進同一個檔案的修改會被無聲蓋掉，事後不一定救得回（這次靠的是對方 session 在 `~/.claude/file-history/` 留下的備份）
- 包含範例（input → output 形式），但不要為了範例而範例
- 寫完隔一段時間再回看，砍掉 dead weight

---

## 2. Rule 組織

### 該放哪個目錄

`~/.claude/rules/` 是可演化的目錄樹，無強制結構。新增 rule 時：

1. 先 `ls ~/.claude/rules/` 看當前分類
2. 找性質最貼近的既有位置放入
3. 不屬於任何既有分類時，**可以新增子目錄**——前提：這個分類預期會累積 **2+ 個 rule**。不要為單一檔案開目錄
4. 邊界模糊時先放最接近位置，等同類累積到 2+ 再切目錄（YAGNI）

判斷分類性質時的概念維度（非強制目錄名）：

| 性質 | 特徵 |
|------|------|
| 核心原則 | 跨領域、跨情境的基礎規範（適合放共用目錄） |
| 流程導向 | 特定 workflow 的步驟規範（適合放流程類目錄） |
| 領域指引 | 特定領域/工具的專屬規範（適合放頂層或領域目錄） |

實際目錄名以當前 `~/.claude/rules/` 結構為準。

### Rule 必要性檢查

寫 rule 前先問：
- 是不是**每個 session 都該知道**的規範？
- 是不是**跨專案/跨任務**通用的行為約束？

兩個都「是」才適合 rule。否則考慮 skill（情境觸發）或 memory（個人化 context）。

例外只放寬第一問：要擋的失效發生在某個輸出寫出來的當下，而寫出之前沒有看得見的訊號（指令、檔案、使用者的話）能讓 skill 載入時，第一問視為「是」。skill 要先載入才生效，description 或 routing.md 的觸發都一樣。第二問「跨專案／跨任務通用」照舊要答「是」。有看得見的訊號時（例如即將編輯 `.go` 檔），照舊走 skill 加 routing.md 的 first-move guard。代價是這幾行每個 session 都付 token，換來的是失效那一刻它已經在 context 裡。

### Rule 大小與寫法

Rule 載入到每個 session 的 system context，每行都付 token。寫 rule 時：

- 一條規範一行，不堆砌範例
- 通則與具體條文分開放。寫判準的那類 rule 只留跨情境成立的判斷依據，不放路徑、檔名、單一指令的行為；具體陷阱另外歸檔（`tool-constraints.md` 這類），一節一個，那裡本來就該寫具體
- 檢查：一條規範拿掉實例之後還講得出該怎麼做嗎？講得出 → 實例是贅肉，砍掉；講不出 → 它不是判準而是具體條文，搬去放具體條文的檔案
- 超過 100 行先想是不是該拆成 skill

### Rule 可以引用 skill

Rule → Skill 的 reference 是**允許**的（如 rule 中寫「處理 X 情境時 invoke `/Y` skill」）。skill 解耦原則只適用 skill ↔ skill 之間，不適用 rule → skill。

理由：rule 是行為規範，引導使用者進入特定 workflow（skill）是 rule 的合理職責。

---

## 3. Memory hygiene

### Type 規範（必須對應）

| Type | 用途 |
|------|------|
| `user` | 使用者角色、偏好、技能背景 |
| `feedback` | 使用者糾正過的行為（含 why） |
| `project` | 進行中的工作 context（含 why） |
| `reference` | 外部系統指標（Linear、Slack、Grafana 等） |

### 該寫 vs 不該寫

**該寫**：
- 跨 session 都有價值的個人化資訊
- 使用者明確要求記住的事
- 非顯然從程式碼可推導的決策背景

**不該寫**：
- 可從 git log / 程式碼 / CLAUDE.md 推導出的資訊
- 短期任務狀態（用 plan / task 而非 memory）
- 解 bug 的具體 fix（commit message 更適合）
- 過時即作廢的資訊（活動、deadline）
- 寫得成通用行為約束的東西——那是 rule，寫進 `~/.claude/rules/`；memory 不是具體規範的收容所

### MEMORY.md 維護

- MEMORY.md 是 index 不是內容，每行 < 150 字元
- 個別 memory 寫獨立檔，frontmatter 含 name / description / type
- 過時 memory 主動刪除，不要堆積

---

## 4. Plugin 評估

### 啟用前該想

- 此 plugin 含哪些 skill / agent / hook / command？
- 與自家 skill 是否重疊？
- frontmatter（特別是 model）是否合理？plugin 通常**無法修改其 frontmatter**

### 與自家 skill 重疊時

- 優先用自家版本（內容可調整；frontmatter 的 model 對自動觸發的 skill 僅為意圖聲明，見「Skill model 與 effort 的實際效力」）
- 重疊嚴重就 disable plugin
- 不要試圖改 plugin SKILL.md（會被升版覆蓋）

### Triggering 衝突

兩個 skill 描述相近時，main agent 可能誤觸或不一致觸發。重疊時：
- 修改自家 skill description 加區分性關鍵字
- 或直接 disable 衝突 plugin

---

## 5. Hook vs Rule vs Skill vs scripts/ vs Memory 決策

收到「該怎麼把這條知識/規範存起來」的問題時：

```
這條知識的本質是什麼？

→ 自動執行、不需 agent 思考的行為（"從現在起每次 X 都做 Y"）
   = Hook（settings.json 的 hooks 欄位，shell 腳本）

→ 個人/專案的事實（who I am、what I prefer、project context）
   = Memory

→ 每個 session 都該遵守的行為規範
   = Rule（放 ~/.claude/rules/）

→ 特定情境觸發時才需要的程序性知識（多步驟流程、checklist）
   = Skill（放 ~/.claude/skills/）
   ↳ 其中「每步是固定指令、而散文每次跑會填出不同結果」的那幾步
     = 該 skill 的 scripts/（SKILL.md 只留呼叫方式與 VERDICT 怎麼讀）
```

最後一支是**巢狀的，不是並列的**：「多步驟流程」這一支會先命中，所以走到 Skill 之後要再問一次那個子問題。寫成第五個並列選項時，由上往下走的人永遠到不了它。

五者特徵：

| 類型 | 觸發 | 執行者 | 成本 |
|------|------|--------|------|
| Hook | 事件自動 | shell 腳本 | 幾乎零（不耗 token） |
| Rule | 每 session 載入 | agent 思考時納入 | 每 session token |
| Skill | 條件觸發 | agent 主動讀取 | 觸發時 token |
| Skill 的 scripts/ | skill 流程中呼叫 | shell / python，agent 只讀輸出 | 只付輸出那幾行 |
| Memory | 持續性事實 | 自動載入 context | 每 session token |

判斷模糊時：
- 要擋的失效發生在輸出寫出來的當下、寫出之前沒有看得見的訊號能讓 skill 載入 → 偏 **rule**，優先於下面的「偶爾才用到 → skill」（判準與界線見 §2〈Rule 必要性檢查〉的例外）
- 內容含「每次 X 都自動 Y」、不需 agent 判斷 → 偏 **hook**
- 內容含「步驟 1...步驟 2...」 → 偏 **skill**
- 步驟本身是固定指令、而散文每次跑會填出不同結果 → 偏 **scripts/**（判準與界線見 §1 那三節）
- 內容含「應該 X、不要 Y」 → 偏 **rule**
- 內容含「我是 X、我偏好 Y」 → 偏 **memory**

選擇原則：
- 自動化（不需 agent 介入）→ hook
- 每 session 都用到 → rule 划算
- 偶爾才用到 → skill 省 token
- 已經在用、而同輸入跑出不同輸出 → scripts/（「希望它一致」不算——那對幾乎每個步驟都成立）
- 跨 session 個人化 → memory

---

## 6. 何時不該編碼（YAGNI）

不是每個 pattern 都該變成 hook / rule / skill / memory。考慮：

- **一次性任務**：直接做，不寫
- **已有覆蓋**：grep `~/.claude/rules/`、`~/.claude/skills/`、`MEMORY.md` 確認沒重複；有就強化既有，不重建
- **不確定會重複**：等到第二次出現再決定
- **半成品**：寫一半放著比沒寫更糟，要寫就寫完

一個例外方向，否則這一節會擋掉該做的事：**已經在用**、而且每次跑要 agent 當場填出不同結果的既有散文，不受「等第二次出現」約束——它不是預測未來需求，它現在就在產生不一致。判準與界線見 §1〈何時把散文轉成 script〉與〈什麼不該轉〉。

「先寫起來放著」是 over-engineering，會累積垃圾配置。等到 friction 出現時再針對性建立，比預測未來需求準確。
