# 外部做法參考

調整 skill 時，改動屬於下面某一類，就先讀那一類列出的來源，看別人怎麼處理同一個問題，再列做法表。這份只放「去哪裡讀、找哪一段」，不抄原文——兩個來源都會更新，抄進來的會過期。

**讀之前先對版本。** 下面的錨點與描述是在「上次讀的版本」上確認的。版本不同就重讀原文、更新這份，不要相信這裡的描述。

| 來源 | 上次讀的版本 | 怎麼讀 |
|---|---|---|
| Claude Code 內建 skill | claude 2.1.302 | prompt 寫在執行檔裡，沒有獨立檔案。`B=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$(command -v claude)")`，`strings -n 8 "$B" > <scratch>/cc-strings.txt`，再 `grep -n -F '<錨點>'` 定位。用錨點字串，不用行號：每次改版行號都會變。錨點只取 ASCII 片段——prompt 裡的破折號在執行檔中存成跳脫序列，照畫面抄會搜不到。`strings` 那一步可能被權限擋下（auto mode 實測擋過）；被擋時不要換指令繞過，在做法表下那一行寫「內建原文未讀：被權限擋」，並請使用者在提示列用 `!` 前綴自己跑那兩行。版本：`claude --version` |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | commit `aeac41d4` | `gh api "repos/addyosmani/agent-skills/contents/<路徑>" --jq .content \| base64 -d`。版本：`gh api repos/addyosmani/agent-skills/commits/HEAD --jq .sha` |
| [obra/superpowers](https://github.com/obra/superpowers) | commit `bb92a777` | `gh api "repos/obra/superpowers/contents/<路徑>?ref=<sha>" --jq .content \| base64 -d`。版本：`gh api repos/obra/superpowers/commits/HEAD --jq .sha`。它也收在官方 plugin 市集 `claude-plugins-official`，裝了才會載入；不是內建 |

標「未讀」的條目只確認過路徑存在，沒讀過內容；用到時先讀，讀完把「回答什麼問題」補上。

## Review／定級

- **Claude Code 內建 `/code-review`**（在 claude 執行檔裡，錨點 `Verify (1-vote`、`mechanism is real, trigger is uncertain`）：多支 finder 各從一個固定角度找候選（逐行掃、被刪掉的檢查在哪重建、沿呼叫者往外查、語言陷阱、包裝層轉發），每則候選配一支 verifier 判 CONFIRMED／PLAUSIBLE／REFUTED，最後補掃一輪漏掉的。回答：「機制成立但觸發不確定」怎麼定級（PLAUSIBLE，保留不丟）、什麼才算推翻（REFUTED 要能從程式碼建構出來）、找候選要從哪些角度。注意它依 model 與 effort 等級跑不同流程，有的只有單一 pass、沒有獨立驗證；實際跑的是哪一套，看輸出第一行印的流程標籤。
- [addyosmani/agent-skills — agents/code-reviewer.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/agents/code-reviewer.md)：第 6 條「If you're uncertain about something, say so and suggest investigation rather than guessing」。回答：拿不準要不要報、要報到什麼程度。
- [addyosmani/agent-skills — skills/code-review-and-quality/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/code-review-and-quality/SKILL.md)：等級分 Critical／Required／Optional／Nit／FYI。回答：等級怎麼切、各級要作者做什麼。
- [obra/superpowers — skills/requesting-code-review/SKILL.md](https://github.com/obra/superpowers/blob/bb92a777/skills/requesting-code-review/SKILL.md)：未讀。

## 規劃

- **Claude Code 內建 `/batch`**（在 claude 執行檔裡，錨點 `## Phase 1: Research and Plan`）：不是一般的規劃方法，是把大型改動拆給多支背景 agent、各開一個 PR 的流程（研究與規劃 → 計畫核准後派工 → 追進度）。回答：一個改動拆成多個獨立單位時，怎麼切、怎麼派、怎麼追。
- [addyosmani/agent-skills — skills/planning-and-task-breakdown/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/planning-and-task-breakdown/SKILL.md)：〈Step 4〉每項的 Acceptance criteria 與 Verification、〈Step 5〉每 2–3 項一個 checkpoint、末段指向 Definition of Done。回答：每一項要寫什麼才算可驗證，以及逐項驗收與每次都要過的固定標準怎麼分工。
- [addyosmani/agent-skills — references/definition-of-done.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/references/definition-of-done.md)：〈Definition of Done vs. Acceptance Criteria〉表與〈Correctness〉。回答：哪些標準是每個改動都要過的（沒有回歸、在執行期實際驗過）、哪些依項目而變。只到清單層級，沒寫怎麼列出要回歸的路徑。
- [addyosmani/agent-skills — skills/spec-driven-development/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/spec-driven-development/SKILL.md)：每項 Acceptance／Verify 兩欄、階段間設 checkpoint。回答：與 planning 那份相同的問題，從規格出發的版本。
- [addyosmani/agent-skills — skills/incremental-implementation/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/incremental-implementation/SKILL.md)：「After each increment… existing tests still pass」。回答：每一片之後要過什麼。只要求既有測試，與 x-plan〈每一片的循環〉同一層。
- [addyosmani/agent-skills — skills/shipping-and-launch/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/shipping-and-launch/SKILL.md)：staging 的「Manual smoke test of critical flows」。回答：出貨前要在接近正式的環境跑關鍵流程；沒說哪些算關鍵。
- [obra/superpowers — skills/writing-plans/SKILL.md](https://github.com/obra/superpowers/blob/bb92a777/skills/writing-plans/SKILL.md)：每個 task 帶「A verification step: the command to run and the output that means it」。回答：驗證步驟要寫到指令與預期輸出。
- [obra/superpowers — skills/dispatching-parallel-agents/SKILL.md](https://github.com/obra/superpowers/blob/bb92a777/skills/dispatching-parallel-agents/SKILL.md)：〈When to Use〉與〈When NOT to Use〉。回答：幾個問題什麼時候可以分給多支 agent 並行（彼此獨立、不共用狀態；相關的失敗先一起查），每支 agent 的 prompt 要帶什麼（範圍、目標、限制、要回傳什麼），回來之後先查彼此有沒有改到同一處再整合。
- [obra/superpowers — skills/subagent-driven-development/SKILL.md](https://github.com/obra/superpowers/blob/bb92a777/skills/subagent-driven-development/SKILL.md)：〈Model Selection〉。回答：subagent 依角色選哪一級 model、為什麼要明確指定（沒指定就繼承 session 的 model），以及「turn 數比 token 單價重要」這條取捨。

## 驗證

- [addyosmani/agent-skills — skills/test-driven-development/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/test-driven-development/SKILL.md)：〈The Prove-It Pattern〉。回答：bug 修正要先重現原症狀、再修、再驗它消失。
- [obra/superpowers — skills/verification-before-completion/SKILL.md](https://github.com/obra/superpowers/blob/bb92a777/skills/verification-before-completion/SKILL.md)：〈Common Failures〉表的「Regression test works｜Red-green cycle verified」與〈Key Patterns〉的 red-green 步驟。回答：一個證據要證明它分得出兩種情況才算數，只跑一次通過不算。

## 設計

- [addyosmani/agent-skills — skills/api-and-interface-design/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/api-and-interface-design/SKILL.md)：〈6. Honouring an Idempotency Key〉末段「Every call has three outcomes, not two: success, failure, and unknown」。回答：一個依賴外部呼叫的設計，除了成功與失敗，還要處理結果不明的那一種；逾時不代表沒生效。
- [addyosmani/agent-skills — skills/idea-refine/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/idea-refine/SKILL.md)：〈Phase 2: Evaluate & Converge〉第 3 步「Surface hidden assumptions」。回答：每個方向要寫出押注為真但沒驗過的事、什麼會讓它失敗、刻意忽略什麼。寫法是警覺型，靠作者自己想到。
- [addyosmani/agent-skills — skills/interview-me/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/interview-me/SKILL.md)：〈The Process〉Step 1–6，一次問一題、每題附自己的猜測，到能預測對方回答（約 95% 信心）才停。回答：需求缺「誰、為什麼、怎樣算成功、主要限制」時，怎麼問到使用者真正要的，而不是自己默默補上。

## Debug

- [addyosmani/agent-skills — skills/debugging-and-error-recovery/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/debugging-and-error-recovery/SKILL.md)：未讀。內建的 `debug` 是開 Claude Code 自己的 debug log，不是查程式錯誤，不列。
- [obra/superpowers — skills/systematic-debugging/SKILL.md](https://github.com/obra/superpowers/blob/bb92a777/skills/systematic-debugging/SKILL.md)：〈The Iron Law〉與〈Common Rationalizations〉。回答：根因沒查完之前能不能提修法（不能），以及修法連續失敗之後該停在哪裡（3 次以上改成質疑做法本身）。

## Skill 撰寫與驗證

- [obra/superpowers — skills/writing-skills/SKILL.md](https://github.com/obra/superpowers/blob/bb92a777/skills/writing-skills/SKILL.md)：〈TDD Mapping for Skills〉、〈Skill Discovery Optimization〉與〈Separate files for〉。回答：怎麼證明一支 skill 有效（先讓 subagent 在沒有它的情況下跑、看它失敗，再寫、再看它通過）、description 該寫什麼（只寫觸發條件，不摘要流程），以及什麼內容該拆成獨立檔（100 行以上的大型參考資料、可重用工具），原則與概念留在 SKILL.md。
