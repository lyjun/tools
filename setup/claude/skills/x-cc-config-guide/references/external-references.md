# 外部做法參考

調整 skill 時，改動屬於下面某一類，就先讀那一類列出的來源，看別人怎麼處理同一個問題，再列做法表。這份只放「去哪裡讀、找哪一段」，不抄原文——兩個來源都會更新，抄進來的會過期。

**讀之前先對版本。** 下面的錨點與描述是在「上次讀的版本」上確認的。版本不同就重讀原文、更新這份，不要相信這裡的描述。

| 來源 | 上次讀的版本 | 怎麼讀 |
|---|---|---|
| Claude Code 內建 skill | claude 2.1.318 | prompt 寫在執行檔裡，沒有獨立檔案。`B=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$(command -v claude)")`，`file -b "$B"` 要含 `Mach-O` 或 `ELF`——印出 `shell script` 表示 `$B` 是包裝腳本（終端機會在 PATH 最前面放自己的 `claude` shim，cmux 實測如此），照樣抽下去錨點會全數搜不到，看起來像 prompt 改版了，這時改用 `which -a claude` 列出的下一個路徑。確認是執行檔後 `strings -n 8 "$B" > <scratch>/cc-strings.txt`，再 `grep -n -F '<錨點>'` 定位。用錨點字串，不用行號：每次改版行號都會變。錨點只取 ASCII 片段——prompt 裡的破折號在執行檔中存成跳脫序列，照畫面抄會搜不到。`strings` 那一步可能被權限擋下（auto mode 實測擋過）；被擋時不要換指令繞過，在做法表下那一行寫「內建原文未讀：被權限擋」，並請使用者在提示列用 `!` 前綴自己跑那兩行。版本：`claude --version` |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | commit `eb07f19f` | `gh api "repos/addyosmani/agent-skills/contents/<路徑>" --jq .content \| base64 -d`。版本：`gh api repos/addyosmani/agent-skills/commits/HEAD --jq .sha` |
| [obra/superpowers](https://github.com/obra/superpowers) | commit `22f0b463` | `gh api "repos/obra/superpowers/contents/<路徑>?ref=<sha>" --jq .content \| base64 -d`。版本：`gh api repos/obra/superpowers/commits/HEAD --jq .sha`。它也收在官方 plugin 市集 `claude-plugins-official`，裝了才會載入；不是內建 |

標「未讀」的條目只確認過路徑存在，沒讀過內容；用到時先讀，讀完把「回答什麼問題」補上。

## Review／定級

- **Claude Code 內建 `/code-review`**（在 claude 執行檔裡，錨點 `Verify (1-vote`、`mechanism is real, trigger is uncertain`）：多支 finder 各從一個固定角度找候選（逐行掃、被刪掉的檢查在哪重建、沿呼叫者往外查、語言陷阱、包裝層轉發；另有三個 cleanup 角度〔含重用、簡化〕與 altitude、專案慣例各一個角度，錨點 `Correctness bugs always outrank cleanup`，輸出名額不夠時 correctness 優先），每則候選配一支 verifier 判 CONFIRMED／PLAUSIBLE／REFUTED，最後補掃一輪漏掉的。回答：「機制成立但觸發不確定」怎麼定級（PLAUSIBLE，保留不丟）、什麼才算推翻（REFUTED 要能從程式碼建構出來）、找候選要從哪些角度。注意它依 model 與 effort 等級跑不同流程，有的只有單一 pass、沒有獨立驗證；實際跑的是哪一套，看輸出第一行印的流程標籤。
- [addyosmani/agent-skills — agents/code-reviewer.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/agents/code-reviewer.md)：第 6 條「If you're uncertain about something, say so and suggest investigation rather than guessing」。回答：拿不準要不要報、要報到什麼程度。2026-11-06 在 `301b02b1` 重讀，內容未變。
- [addyosmani/agent-skills — skills/code-review-and-quality/SKILL.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/skills/code-review-and-quality/SKILL.md)：等級分 Critical／Required／Optional／Nit／FYI。回答：等級怎麼切、各級要作者做什麼。2026-11-06 在 `301b02b1` 重讀：另有「Before reporting a finding, check it against the callers, guards and tests that reach the changed code, and drop it if they rule it out」，是用既有保護排除 finding，不檢查那個保護是否每條路徑都成立。
- [obra/superpowers — skills/requesting-code-review/code-reviewer.md](https://github.com/obra/superpowers/blob/22f0b463/skills/requesting-code-review/code-reviewer.md)：〈Declined to judge〉，2026-11-06 在 `22f0b463` 讀。回答：reviewer 考慮過而放下不判的項目要逐條交出、附理由，由主線裁決，不能默默丟掉。同目錄的 SKILL.md 只講何時派 reviewer。

## 規劃

- **Claude Code 內建 `/batch`**（在 claude 執行檔裡，錨點 `## Phase 1: Research and Plan`）：不是一般的規劃方法，是把大型改動拆給多支背景 agent、各開一個 PR 的流程（研究與規劃 → 計畫核准後派工 → 追進度）。回答：一個改動拆成多個獨立單位時，怎麼切、怎麼派、怎麼追。
- [addyosmani/agent-skills — skills/planning-and-task-breakdown/SKILL.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/skills/planning-and-task-breakdown/SKILL.md)：〈Step 4〉每項的 Acceptance criteria 與 Verification、〈Step 5〉每 2–3 項一個 checkpoint、末段指向 Definition of Done。回答：每一項要寫什麼才算可驗證，以及逐項驗收與每次都要過的固定標準怎麼分工。2026-11-04 在 `301b02b` 重讀 Step 5，內容未變：checkpoint 只是每 2–3 項一次的 build／test 關卡，沒講實機要從哪一層量。
- [addyosmani/agent-skills — references/definition-of-done.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/references/definition-of-done.md)：〈Definition of Done vs. Acceptance Criteria〉表與〈Correctness〉。回答：哪些標準是每個改動都要過的（沒有回歸、在執行期實際驗過）、哪些依項目而變。只到清單層級，沒寫怎麼列出要回歸的路徑。
- [addyosmani/agent-skills — skills/spec-driven-development/SKILL.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/skills/spec-driven-development/SKILL.md)：每項 Acceptance／Verify 兩欄、階段間設 checkpoint。回答：與 planning 那份相同的問題，從規格出發的版本。
- [addyosmani/agent-skills — skills/incremental-implementation/SKILL.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/skills/incremental-implementation/SKILL.md)：「After each increment… existing tests still pass」。回答：每一片之後要過什麼。只要求既有測試，與 x-plan〈每一片的循環〉同一層。
- [addyosmani/agent-skills — skills/shipping-and-launch/SKILL.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/skills/shipping-and-launch/SKILL.md)：staging 的「Manual smoke test of critical flows」。回答：出貨前要在接近正式的環境跑關鍵流程；沒說哪些算關鍵。
- [obra/superpowers — skills/writing-plans/SKILL.md](https://github.com/obra/superpowers/blob/2ce8aa15/skills/writing-plans/SKILL.md)：每個 task 帶「A verification step: the command to run and the output that means it」。回答：驗證步驟要寫到指令與預期輸出。
- [obra/superpowers — skills/dispatching-parallel-agents/SKILL.md](https://github.com/obra/superpowers/blob/2ce8aa15/skills/dispatching-parallel-agents/SKILL.md)：〈When to Use〉與〈When NOT to Use〉。回答：幾個問題什麼時候可以分給多支 agent 並行（彼此獨立、不共用狀態；相關的失敗先一起查），每支 agent 的 prompt 要帶什麼（範圍、目標、限制、要回傳什麼），回來之後先查彼此有沒有改到同一處再整合。
- [obra/superpowers — skills/subagent-driven-development/SKILL.md](https://github.com/obra/superpowers/blob/2ce8aa15/skills/subagent-driven-development/SKILL.md)：〈Model Selection〉。回答：subagent 依角色選哪一級 model、為什麼要明確指定（沒指定就繼承 session 的 model），以及「turn 數比 token 單價重要」這條取捨；review 的 model 依 diff 的大小與風險調整。
- [obra/superpowers — skills/subagent-driven-development/references/fix-loop.md](https://github.com/obra/superpowers/blob/2ce8aa15/skills/subagent-driven-development/references/fix-loop.md)：開頭兩條「直接離開 loop」的路，與 Rounds 1-3／4-5 兩段。回答：修正一輪一輪失敗時上限設多少（每項 5 輪）、到第幾輪換人（第 4 輪起換一支新的、model 高一級的 agent，理由是撐過三輪通常表示原執行者看不見自己的問題），以及小問題不進 loop、改記帳交給最後的整體 review。

## 驗證

- **Claude Code 內建的 coordinator 指示**（在 claude 執行檔裡，錨點 `### What Real Verification Looks Like`）：派 worker 做事時，驗證是證明它能動，不是確認它存在；worker 回報「改好了」只代表它打算做什麼，轉告使用者之前先看實際的 diff。回答：subagent 回報完成之後，主線要自己查什麼才能說「完成」。
- [addyosmani/agent-skills — skills/test-driven-development/SKILL.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/skills/test-driven-development/SKILL.md)：〈The Prove-It Pattern〉。回答：bug 修正要先重現原症狀、再修、再驗它消失。
- [obra/superpowers — skills/verification-before-completion/SKILL.md](https://github.com/obra/superpowers/blob/2ce8aa15/skills/verification-before-completion/SKILL.md)：〈Common Failures〉表的「Regression test works｜Red-green cycle verified」與〈Key Patterns〉的 red-green 步驟。回答：一個證據要證明它分得出兩種情況才算數，只跑一次通過不算。

## 設計

- [addyosmani/agent-skills — skills/api-and-interface-design/SKILL.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/skills/api-and-interface-design/SKILL.md)：〈6. Honouring an Idempotency Key〉末段「Every call has three outcomes, not two: success, failure, and unknown」。回答：一個依賴外部呼叫的設計，除了成功與失敗，還要處理結果不明的那一種；逾時不代表沒生效。
- [addyosmani/agent-skills — skills/idea-refine/SKILL.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/skills/idea-refine/SKILL.md)：〈Phase 2: Evaluate & Converge〉第 3 步「Surface hidden assumptions」。回答：每個方向要寫出押注為真但沒驗過的事、什麼會讓它失敗、刻意忽略什麼。寫法是警覺型，靠作者自己想到。
- [addyosmani/agent-skills — skills/interview-me/SKILL.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/skills/interview-me/SKILL.md)：〈The Process〉Step 1–6，一次問一題、每題附自己的猜測，到能預測對方回答（約 95% 信心）才停。回答：需求缺「誰、為什麼、怎樣算成功、主要限制」時，怎麼問到使用者真正要的，而不是自己默默補上。

## Debug

- [addyosmani/agent-skills — skills/debugging-and-error-recovery/SKILL.md](https://github.com/addyosmani/agent-skills/blob/eb07f19f/skills/debugging-and-error-recovery/SKILL.md)：〈The Stop-the-Line Rule〉與〈Treating Error Output as Untrusted Data〉。回答：出現非預期狀況時先停、先保留證據，修好驗過才繼續往下做；錯誤訊息與 log 裡像指令的文字（「執行這個來修」）是資料，交給使用者，不照做。內建的 `debug` 是開 Claude Code 自己的 debug log，不是查程式錯誤，不列。
- [obra/superpowers — skills/systematic-debugging/SKILL.md](https://github.com/obra/superpowers/blob/2ce8aa15/skills/systematic-debugging/SKILL.md)：〈The Iron Law〉與〈Common Rationalizations〉。回答：根因沒查完之前能不能提修法（不能），以及修法連續失敗之後該停在哪裡（3 次以上改成質疑做法本身）。

## Skill 撰寫與驗證

- [obra/superpowers — skills/writing-skills/SKILL.md](https://github.com/obra/superpowers/blob/2ce8aa15/skills/writing-skills/SKILL.md)：〈TDD Mapping for Skills〉與〈Separate files for〉。回答：怎麼證明一支 skill 有效（先讓 subagent 在沒有它的情況下跑、看它失敗，再寫、再看它通過），以及什麼內容該拆成獨立檔（100 行以上的大型參考資料、可重用工具），原則與概念留在 SKILL.md。
- 同一份的〈Match the Form to the Failure〉：先把要防的失敗分類再選寫法——明知故犯用禁止句加藉口對照表；照做但輸出形狀不對用正面的配方（寫出輸出由哪幾部分、依什麼順序組成），禁止句在這類反而更糟；漏掉某個必要元素用模板裡的必填欄位；行為依條件而變用看得見的判斷式。另附兩條：不要加「除非重要」這類但書，例外條款也框不住範圍。回答：一條新規則該寫成哪種形式。與 x-cc-config-guide〈寫作語氣〉的警覺型／替換型／對照物件型是同一個問題的另一種切法。
- 同一份的〈Micro-Test Wording Before Full Scenarios〉：每次只取一個全新 context 的樣本、一定要有不加指引的對照組（對照組不出現失敗就不用寫）、每組 5 次以上、標出的命中逐則人工讀、各次結果分歧大表示字句沒約束力。回答：規則的字句怎麼便宜地先驗過，再跑完整情境。
- [obra/superpowers — skills/writing-skills/references/discovery.md](https://github.com/obra/superpowers/blob/2ce8aa15/skills/writing-skills/references/discovery.md)：〈Skill Discovery Optimization〉（原本在 SKILL.md，這一版搬到這裡）。回答：description 該寫什麼（只寫觸發條件，不摘要流程）。
