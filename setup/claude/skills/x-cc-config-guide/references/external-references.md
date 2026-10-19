# 外部做法參考

調整 skill 時，改動屬於下面某一類，就先讀那一類列出的來源，看別人怎麼處理同一個問題，再列做法表。這份只放「去哪裡讀、找哪一段」，不抄原文——兩個來源都會更新，抄進來的會過期。

**讀之前先對版本。** 下面的錨點與描述是在「上次讀的版本」上確認的。版本不同就重讀原文、更新這份，不要相信這裡的描述。

| 來源 | 上次讀的版本 | 怎麼讀 |
|---|---|---|
| Claude Code 內建 skill | claude 2.1.302 | prompt 寫在執行檔裡，沒有獨立檔案。`B=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$(command -v claude)")`，`strings -n 8 "$B" > <scratch>/cc-strings.txt`，再 `grep -n -F '<錨點>'` 定位。用錨點字串，不用行號：每次改版行號都會變。錨點只取 ASCII 片段——prompt 裡的破折號在執行檔中存成跳脫序列，照畫面抄會搜不到。`strings` 那一步可能被權限擋下（auto mode 實測擋過）；被擋時不要換指令繞過，在做法表下那一行寫「內建原文未讀：被權限擋」，並請使用者在提示列用 `!` 前綴自己跑那兩行。版本：`claude --version` |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | commit `aeac41d4` | `gh api "repos/addyosmani/agent-skills/contents/<路徑>" --jq .content \| base64 -d`。版本：`gh api repos/addyosmani/agent-skills/commits/HEAD --jq .sha` |

標「未讀」的條目只確認過路徑存在，沒讀過內容；用到時先讀，讀完把「回答什麼問題」補上。

## Review／定級

- **Claude Code 內建 `/code-review`**（在 claude 執行檔裡，錨點 `Verify (1-vote`、`mechanism is real, trigger is uncertain`）：多支 finder 各從一個固定角度找候選（逐行掃、被刪掉的檢查在哪重建、沿呼叫者往外查、語言陷阱、包裝層轉發），每則候選配一支 verifier 判 CONFIRMED／PLAUSIBLE／REFUTED，最後補掃一輪漏掉的。回答：「機制成立但觸發不確定」怎麼定級（PLAUSIBLE，保留不丟）、什麼才算推翻（REFUTED 要能從程式碼建構出來）、找候選要從哪些角度。注意它依 model 與 effort 等級跑不同流程，有的只有單一 pass、沒有獨立驗證；實際跑的是哪一套，看輸出第一行印的流程標籤。
- [addyosmani/agent-skills — agents/code-reviewer.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/agents/code-reviewer.md)：第 6 條「If you're uncertain about something, say so and suggest investigation rather than guessing」。回答：拿不準要不要報、要報到什麼程度。
- [addyosmani/agent-skills — skills/code-review-and-quality/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/code-review-and-quality/SKILL.md)：等級分 Critical／Required／Optional／Nit／FYI。回答：等級怎麼切、各級要作者做什麼。

## 規劃

- **Claude Code 內建 `/batch`**（在 claude 執行檔裡，錨點 `## Phase 1: Research and Plan`）：不是一般的規劃方法，是把大型改動拆給多支背景 agent、各開一個 PR 的流程（研究與規劃 → 計畫核准後派工 → 追進度）。回答：一個改動拆成多個獨立單位時，怎麼切、怎麼派、怎麼追。
- [addyosmani/agent-skills — skills/planning-and-task-breakdown/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/planning-and-task-breakdown/SKILL.md)：未讀。
- [addyosmani/agent-skills — skills/spec-driven-development/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/spec-driven-development/SKILL.md)：未讀。

## 設計

- [addyosmani/agent-skills — skills/api-and-interface-design/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/api-and-interface-design/SKILL.md)：未讀。
- [addyosmani/agent-skills — skills/idea-refine/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/idea-refine/SKILL.md)：未讀。
- [addyosmani/agent-skills — skills/interview-me/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/interview-me/SKILL.md)：未讀。

## Debug

- [addyosmani/agent-skills — skills/debugging-and-error-recovery/SKILL.md](https://github.com/addyosmani/agent-skills/blob/aeac41d4/skills/debugging-and-error-recovery/SKILL.md)：未讀。內建的 `debug` 是開 Claude Code 自己的 debug log，不是查程式錯誤，不列。
