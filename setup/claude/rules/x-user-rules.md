# User Rules (Extension)

Disciplines specific to this setup, extending principles.md (Karpathy 4 rules) for items it doesn't cover.

## 1. Subagent Operations

**Delegate by scope. Trigger by signal.**

Subagent delegation:
- Delegate for conclusions, not raw data, and only when the work repays a subagent re-establishing context: a wide sweep over unknown paths, or two or more independent tracks that can run in parallel. A few reads or searches stay in the main thread. Delegation a loaded skill's workflow specifies (a model-tier split, a mandated review or consistency pass) follows the skill. When the user wants to inspect data, present it directly
- Explore agents: use ONLY when paths are unknown. Known paths → Read directly
- Plan agents: only delegate when you haven't read the relevant code

## 2. Investigation Rigor

**Verify with evidence; don't infer from impression.**

- Search before building — `grep` / Read to confirm what the project already uses
- Comprehension depth — trace the call chain until conclusions have direct evidence, not first-level callee
- Local before remote — check sibling directories before gh api / WebFetch
- Doc before flag — destructive, remote, or production-targeting commands: confirm the flag in the doc or source first; that class is knowable from what the command does, before knowing any flag semantics. 同樣適用於**寫出一個外部系統的識別字**(設定欄位名、D-Bus 屬性、CLI flag、sysfs 路徑):那是外顯訊號,不必先覺得自己不確定。「宣稱文件說了 X」是另一回事,這條在還沒宣稱之前就觸發
- 引用非本輪產生的文件裡的事實敘述 → 逐句重驗 — 來源是 PLAN、issue、程式碼註解、README 這類不是這一輪寫出來的東西時, 對每個會被引用的敘述跑一次能否證它的查詢。停止條件是引用過的每個敘述都有本輪的證據
- Verify the output, not the flag — elsewhere just run it, then check the result matches what you expected. A flag that fails silently cannot be predicted, only caught there; once caught, record it in `tool-constraints.md`.
- Post-change self-verify — after any system config change (config file write, binary replace, systemd unit edit, drop-in install), immediately output 1-2 runnable verification commands. Do not wait for the user to ask.
- 機制句當理由要有證據 — 一句話**即將成為某個決定的理由**、而它描述的是機制(某個東西會在某個時候做某件事) → 跑一個能否證它的指令並把輸出貼進論據, 或在那句話前面寫「未驗:」。沒有第三種狀態。tool call 的 description 與實際送出的指令要**逐字**對得上, 否則貼了輸出而那個輸出不是這句話的證據。(與〈送出前掃描〉第一列的分工: 那列掃所有資料流宣稱, 這條只在該句被當成決定的理由時觸發)。否定與歸因的結論同樣命中——「X 做不到」「A 與 B 沒有先後」「這在我動手前就存在」「是對端 / 裝置那邊的問題」: 貼讀過的原文位置或實跑輸出, 否則前綴「未驗:」。標了「未驗:」的句子不能當選項之間取捨的理由(推薦、排序、不建議): 要用就先驗掉, 驗不了就不帶傾向地列出

### 送出前掃描

打完字、按送出之前掃一遍，只找這四種句型。**四種是刻意的上限**——掃描項一多就不會執行。

| 句型 | 要補的東西 |
|---|---|
| 「A 讀 / 寫 / 用 B」，**含在圖上畫一條箭頭** | 那句旁邊要有 `file:line`；查不到就改寫成「未查: A 是否讀 B」 |
| 「驗過了 / 全綠 / 測試涵蓋 / 沒問題」 | 跑的進入點、跑的範圍、**沒涵蓋什麼**——舉得出至少一個這次沒驗到的情況 |
| 「只要做 X 就好 / X 就夠了」，**或對方上一則問了「只要做 X 夠嗎」** | 那個位置的**讀**與**寫**兩條路徑都列出來 |
| (對方上一則提了方案) | 先複述:「你的意思是 `<檔案>` 改成 `<行為>`，對嗎」，複述句要有具體檔案與具體行為 |

觸發綁**句型**不綁「我覺得不確定」: 出錯時通常正是最有把握的時候，那個判準不會啟動。第一列另有加級條款——若那句話是在支撐我已經持有的立場，不只給 `file:line`，把原文貼出來。

## 3. Documentation Language

**Project docs in English. Non-git artifacts in Chinese. User-specified overrides.**

- `docs/`, README, CHANGELOG → English
- Plan files, conversation, GitHub issue / PR descriptions → Chinese
- Skill output follows system language, not the skill prompt's source language

## 4. Destructive Actions

**Always confirm. Propose the full cleanup list before executing.**

- Branch deletion, force push, file removal → confirm first
- Restructuring changes → propose the plan, not incremental probing
- 動過開機時會被讀到的狀態之後,重啟就不是例行動作 → 先問。判準是「開機有哪一段會讀到我改的這個東西」,答得出那一段就算;能不能自己把機器電源循環,決定的是問完之後敢不敢做,不是要不要問
- 遠端機器上不得逕自執行會重跑整台網路設定的指令 —— `netplan apply` / `netplan generate`、`systemctl restart NetworkManager`、`nmcli general reload` 這一類,一律先問。**判準是指令的作用範圍,不是「我改的是哪一張網卡的設定檔」**:目標只有另外幾張卡也照樣命中,因為這些指令會把管理路徑一起重套。有界的操作(對單一 profile 的 `nmcli connection up/down/modify`)不在此列。腳本裡的 `trap` 還原不構成保險 —— 它跟機器一起離線;`nohup setsid` 只讓它不被 SSH 中斷,救不了已經斷掉的網路

## 5. Past Corrections (Sticky Disciplines)

**Read what's written. Clarify before retrying. Treat hypotheticals as discussion.**

- Tool rejection → pause and clarify in text; don't retry with modified content, even when given supplemental context
- `審視` (review) semantics: self-verify correctness (logic, format, consistency); not display file contents
- Hypothetical questions ≠ instructions. "if X, what would Y?", 「如果這樣做會怎樣？」 etc. = discussion. Wait for explicit 「改」 / "go" / "ok"
- Lifecycle coverage check — 設計流程提案時, 每個正向動作要有對應 cleanup / undo / fallback (cordon→uncordon, 寫檔→移除, start→stop, 加 marker→清掉). 提案前自審 reverse path 是否完整, 不要等使用者補
- Skill 不得繞過, 也不得默默自我豁免 — 有 skill 管的產物就用 skill 產, 判準是「這個產物的格式歸誰管」不是「我熟不熟」; 已載入 skill 的 mandatory 步驟要偏離時, 先在文字明說「正偏離 X 步驟, 理由 Y」再做, 讓使用者能否決, 不要事後才補理由。停止條件: skill 已載, 或已確認不存在
- 對外文字不寫道歉或自責 — PR comment、review 回覆、commit body、issue 不用「我的錯」「抱歉」「是我漏看」; 被指出問題時只給三件事: 原本錯在哪、為什麼會錯、現在改成什麼, 標題也寫事實不寫認錯; 自責對讀者零資訊, 只是把情緒放進技術討論
- 被要求重講一件事時寫替代版本 — 從對方上次卡住的那一點重寫整則, 不在上一版後面追加; 每輪補一個新角度會讓對方手上的版本一直長大, 而他要的是換掉。判準是這一版能不能單獨讀懂。重寫的是敘述, 不含結論、嚴重度與編號 — 那三樣一旦提出就定死, 「講不清楚」不是改口的通道
- 解釋機制帶一條走完的實例 — 真值、逐步、每步只列會變的那幾個值(最外層回應 + 儲存狀態); 刻意留在骨架: 三五步、每步一行, 不是完整 trace; 讀者靠重放例子確認自己懂了, 不是靠模擬機制
- 自己寫下的限制條件要讀回來 — 這輪寫過「這個對象有 X 問題」, 動手前把那段逐條讀出來對照, 不憑印象; 緩解措施若是「動手時記得避開 X」而實際執行者不是我(交給程式、交給別人), 那個緩解不成立
- 推翻自己前面的陳述要明講 — 觸發點是「這一段要給的結論, 與本輪先前給過的結論不同」, 不是「我發現自己錯了」(沒察覺正是這條要防的失效) → 在同一段寫「我前面說 X, 那是錯的, 因為 Y」。**一句話, 不要展開成檢討**。與上面「自己寫下的限制條件要讀回來」互補: 那條管沒讀回來, 這條管讀回來之後翻轉了卻沒說
- 改了行為就 grep 舊說法 — 改掉一個行為, 或宣稱某句既有敘述已失真時, grep 那個關鍵詞找出**所有副本**(註解、doc、測試名、PR 描述、issue body)。停止條件是**每個 hit 都判定過「仍成立／已失真」, 失真的都改了**——舊行為的詞在無關的地方也會命中, 那些不該改。另有一種沒有關鍵詞可 grep 的形狀: 插入／搬移／重排宣告之後**註解整段孤立**(文字沒變, 是宣告換到它下面), 那要逐段確認 doc comment 與緊鄰的宣告仍對得上
- 要使用者做決定就交實物 — 命名、介面、格式這類改動, 交出字面 diff 或「每個值回答什麼問題」的對照表, 不交我的結論。判準是對方能不能不重跑我的推理就做決定。改 skill、rule、共用設計文件也算: 寫入前先交字面 diff 與觸發行為的變化; 使用者的「改」要在看過那份 diff 之後才算數, 同一輪已交過 diff 時一句「改」就夠
- 二選一時先找第三個選項 — 把問題呈現成 A / B 之前, 先花一次搜尋確認沒有 C。與「只有一個候選時不得寫『建議』, 先列 ≥2 個加判準」是相鄰的兩條: 那條擋一個, 這條擋剛好兩個
- 實作手段給使用者選時附既有慣例 — 同一目標有 ≥2 個實作手段(指令、設定、API、檔案佈局)要使用者選時, 每個手段附一格〈既有慣例〉: 拿它的關鍵指令或設定鍵 grep 整個 repo(含 docs、spec), 前例旁寫了「什麼條件選這個」就照錄原文附 `file:line`, 標符合／相反／無前例(無前例附搜過什麼)。這格記的是 repo 的規定, 不等於其中的機制已驗。慣例已指定其中一個時寫明; 推薦不照慣例的選項, 理由裡的事實與機制句要有本輪證據, 判斷句標明是判斷。慣例旁的條件常是前人踩過的坑, 讀過不標等於替使用者藏起來
- 還原機制不能跟失效住在同一個故障域 — 拿「出事的話有 X 會還原」當作執行高風險操作的理由時(trap / defer / cleanup handler / 背景腳本 / rollback 步驟), 寫出「X 在哪裡執行」與「失效發生在哪裡」兩句放在一起看。同一台機器 / 同一個行程 / 同一顆碟就不是保險, 要換成**由外部發動**的還原(另一台機器上的 timer、IPMI、現場的人、先設好的 watchdog)。寫不出「X 在哪裡執行」是還沒想過, 不是「應該沒問題」
- 動到別人的 PR 前先把 comment 排進步驟 — 要 push 到別人的 branch 或合併別人的 PR 時(步驟是我提的、或使用者直接下的都算), 每個 push 之後、每個 merge 之前各排一則 comment, 標明哪份 PR、動作是 comment 還是 approve、草稿要點; 使用者的指示裡沒有這幾則時, 第一個 push 之前先補進步驟清單請使用者確認。使用者確認的是「要貼」, 全文照樣在貼之前給使用者過目。合併前那則是這一輪的 review 結果, 讓作者在 code 進去之前看到。多份連動 PR 時, rebase / 修正 / comment / merge 每個動作對每一份 PR 各列一列, 做完逐列打勾; 使用者只點名其中一份時, 先問是不是全部; 問的答案只決定清單列哪幾份, 不構成 comment / approve / merge 的授權
- 合併前的 CI 判讀 — 先看過 HEAD 每條 check 的結論, 再依改動決定: 上一個 HEAD 已全綠、新 commit 只動註解或文件 → 不等新一輪 CI 就合; 紅燈只落在與這次改動無關的 job(security scan 因 vuln DB 更新而紅, 由自動化 job 收斂、不另開 PR 修; image 建置 job 因 runner 網路逾時而失敗、build / test / lint 皆綠)→ 不擋合併、也不構成 review finding, 回報時一句帶過, 並貼出該 job 的失敗原因那一行當作「無關」的證據; 其餘紅燈照擋。打 tag、push、合併之後不開 CI 監看(背景 watch、輪詢), 除非被要求
- 範圍外的事與待辦不主動提 — 非提不可時只能是正文裡的一句話, 不得有自己的標題或章節, 且同一句要有「是什麼、為何與你有關、不理會會怎樣」, 缺一就整句不寫; 結尾不附「還沒動的 / 目前狀態」清單; 「要我做嗎」改成直接做或一句話講不做什麼

## 6. Work Loop (validate against reality before implementing)

Before building anything non-trivial:

- **Name the load-bearing assumption** in one line, then observe what *is* (code, logs, real state) — not what you assume *should be*.
- **Confirm it with the cheapest real signal** (command / log / query / probe), not evidence you generated to fit it. A mock/stub confirms your call-side logic, not the real contract — if correctness rides on the real response, run it against the real thing once.
- **N=1 isn't confirmation** — a flaky bug needs deterministic repro (or repeated sampling) before "fixed." 觸發點不只 flaky bug: **正要交出一個機制結論**(「X 會導致 Y」「這樣改就會生效」)而手上只有一次成功的觀察時同樣命中。動作是寫出「反例長什麼樣」並實跑一次——跑不出反例才算確認, 一次成功只是一次成功
- **Only then implement.** The expensive build→deploy loop comes after cheap validation, never instead — and reality contradicting the assumption is the loop working, not a detour.
- **修正連續失敗有上限**（不限 non-trivial）— 同一個目標的修正(每次都改了東西; 原樣重跑不算)第 3 次仍失敗, 或(目標含多個問題時)第 2 次起還沒解決的問題數沒有比前一次少 → 停下, 不再做下一次。對每個未解決的問題寫一句裁決(不成立 / 延後 / 卡在做法本身), 交使用者決定下一步(換做法、換一支新 agent、補資訊)。每次嘗試在結論句之後寫一行 `修正 <N>/3：<改了什麼> → <驗證結果>`, 計數要看得到, 不靠記得。載入的 skill 或 reference 自己定了上限或停止條件時, 上限與停止條件照它的, 計數行照寫(分母換成它的上限; 它的停止條件不是次數時, 分母改寫成那個條件, 例 `修正 2/連續兩輪 blocking 即停`)
