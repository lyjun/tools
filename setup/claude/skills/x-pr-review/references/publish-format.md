# PR-publish Format

This file is the **source of truth** for posting format — render hygiene, the atom shape,
and all three templates. `SKILL.md` (*Posting a review*) carries a copy of the Template
A / C skeletons and the icon↔label map so the shape is in-context on skill load and you
can post without loading this file; **when the two disagree, this file wins** and
`SKILL.md` is what gets corrected. Post via `gh pr review` (approve / request-changes /
comment) or `gh pr comment`. 本格式管的是 review **別人** PR 時貼出去的 comment;總結自己
改動的 PR comment 是另一種產物,不適用(見 `feedback_review_others_pr_no_self_comment`)。

> **範圍**:合併前的閘門式檢查報告是另一種產物(固定 checklist,`pass` / `block` / `nit` / `fail` 是閘門判定、給使用者看、從不 post),**刻意沿用自己的詞彙,不要「統一」成本格式**。嚴重度門檻對應:`block` ≈ `issue (blocking)`、`nit` ≈ `nitpick`。

## Conventions (all templates)

- Open with a one-line **verdict**。收尾行只在 Follow-up 非空時寫(用來說明「有這幾項但不擋」);Follow-up 空的時候省略——`LGTM 👍`、verdict、GitHub 的 APPROVED 狀態已經把「可以合」講了三次。
- Header: `Review recap`.
- Cite evidence inline: `file:line` and commit `sha` throughout.
- **節由 template 定義,不自行增節。** 順手驗過的改動、作者自己列在 PR 描述 / tasks 清單裡的未結事項,都屬於某一個 finding 的一部分——歸進那一點的 atom 底下,不要各開一節。這是 recap 膨脹成散文的起點:一旦有了空章節就會拿機制描述去填,而機制是作者自己寫的,他知道。作者做對的事客觀寫他做了什麼,不寫成「我沒發現的」(對外文字不自責,見 `x-user-rules`)。
- **只寫 review 的內容,不搬閘門結果。** CI 綠不綠、regen 跑了沒、測試存不存在,是**合併前閘門**的產物,不是 review 的內容——閘門報告給使用者看、從不 post,由使用者決定要不要轉告作者。review 輸出不再列一次。順手驗過而**本身構成 finding** 的(例:作者說測試全綠,但 HEAD 的 CI 實際是紅的;或這個 repo 沒開 wire-compat 檢查,contract 變更沒有自動把關)寫進 finding;只是「我看過了」的不寫。這與上一條同源:驗證結果既然要歸進 atom,template 就不該有專門放它的節。
- **哪些內部欄位不隨貼文出去**,對照表在 `SKILL.md` 的 *Output model: internal report* 開頭,以那份為準。這裡只記結果:貼出版從 `問題` 起算,`程式要求` 整段拿掉——作者就是訂那條要求的人。
- **`問題` 那句要三件事:什麼壞了、誰承受、什麼條件下會發生。** 第三項不是在這裡想的——它是內部報告 gate 第 8 關已經查過並寫進 `證據` 的那個觸發條件,貼文只是把它放進句子。race / concurrency finding 例外:觸發條件依 `SKILL.md` 的 Class A/B 格式展開,不壓進這一句。下面 template 的 `<…>` 佔位符是這條的縮寫,不是另一套要求。
- **篇幅。** subject 一行,每條一查核點一行。讀者判準:作者不回頭看 diff,就能看懂什麼壞了、什麼條件下壞、怎麼修。句數與行數是檢查觸發,不是上限:`問題` 超過 2 句、`建議` 超過 3 句,或總長超過門檻(數**非空行**、隨**手寫**改動量,generated / lock 檔不計:< 50 行 → 20 非空行,50–300 行 → 35,> 300 行不設門檻)時,照砍的順序檢查一次:回述作者已知的事 → 同類項合併 → 展開的 atom 收回單行;砍完仍超過就保留,那是這條 finding 需要的長度。< 50 行那個門檻是從一則實際被接受的 recap 校準來的(25 行 contract diff、2 個 finding、17 非空行)。機制 codeblock、時序圖、選項 bullet 不計入;講不清時改用下面的 codeblock 畫機制,不是多寫幾句散文。

**Render hygiene(GitHub markdown 掃讀性)** —— 節與 finding 若與內文同權重,subject 那行不會跳出來,多個 finding 會連成一牆。所以:

- **節與 finding 都用 heading,不要用粗體。** 粗體只是 `<p>` 裡的 `<strong>`:與內文同字級,而且只有 label 那幾個字變粗,撐不起層級。heading 是另一種 block——整行粗、上方留白比段落大、帶 anchor。**但字級只有 `###` 以上才變大**:GitHub 的 `h2` 是 1.5em、`h3` 1.25em,`h4` 與內文同為 1em——所以 `####` 只換來間距,換不到字級,靠它分隔 finding 效果有限。層級固定兩層:**節用 `##`,finding 用 `###`**。
- **不需要 `---` 分隔 atom**——heading 本身已把每個 finding 切成獨立單位。
- **拿不準渲染結果就實測,不要憑 markdown 原始碼猜**:`gh api --method POST /markdown --input -`,帶 `{"text":<body>,"mode":"gfm"}`,再看 block 結構。這條是實務教訓:GitHub comment 會把單一換行渲染成 `<br>`(所以 `問題:` / `建議:` 兩行會分行),但粗體、縮排、bullet 都不建立層級——這兩件事憑讀原始碼都判斷不出來,只有渲染看得到。
- **一個獨立查核點 = 一行 / 一 bullet**:別把多件事(如 gate 已加 / 與 mirror 一致 / middleware chain 相同 / docs 同步)用分號串成一長句、整段不斷行。「連貫成人話」是指**每一行**讀起來像句話,不是把所有點併成一句;分號串到第三件事就該斷行。
- **反過來也別反射性套 `- `**:格式服務內容——真正並列 / 可枚舉的項目才用 bullet,幾句各自獨立的陳述直接分行即可;硬包成 list 會做出它不需要的假結構。全擠成一句、與全塞進 bullet,是同一種矯枉過正的兩個方向。

### Label 用 Conventional Comments 標準詞

分類用 [Conventional Comments](https://conventionalcomments.org/) 的**標準文字
label**,不自創 tag。「是什麼類型」跟「擋不擋 merge」是**兩個正交軸**:類型用
label,擋不擋用 decoration 括號,不把兩者融進同一個記號。

- **label**(是什麼,取 Conventional Comments 常用子集,每個都對應下表一個 icon):`issue` · `nitpick` · `suggestion` · `question` · `note` · `chore` · `praise`
- **decoration**(擋不擋,只在需要時加):`(blocking)` · `(non-blocking)` · `(if-minor)`
- 一則不堆多個 decoration(可讀性)。

### Icon ↔ label(一項一個 icon)

icon 是 label 的**視覺別名**——同一軸、純掃讀用,不承載第二個資訊。每項**只有一
個 icon**;舊版 `✅ 🔵 [nit]` 把「狀態 emoji + 嚴重度 emoji + 文字 tag」疊三層,
正是要消掉的。

| icon | label | 何時 |
|------|-------|------|
| 🔴 | `issue (blocking):` | 必改才能 merge |
| 🟡 | `issue (non-blocking):` | 真問題但不擋(具體 failure mode / ops risk) |
| 🔵 | `nitpick:` | 小事,可改可不改 |
| 💡 | `suggestion:` | 改進提案 |
| ❓ | `question:` | 不確定的疑問 |
| 📝 | `note:` / `chore:` | 提醒 / 雜務(含 docs、PR 描述) |
| 👍 | `praise:` | 稱讚 / LGTM |

### Re-review 解決狀態(Template C)—— 換軸,不疊

再確認時,**舊 finding 的 icon 換成解決狀態**,label 退成純文字;這輪**新** finding
才用嚴重度 icon(上表)。一項永遠只有一個 icon,**絕不 `✅ 🔵` 這樣狀態疊嚴重度**
——因為在再確認情境裡「解到了沒」才是主資訊,嚴重度退成文字即可。

- ✅ 已解 · ⚠️ 部分/表面 · ❌ 未處理/理解偏差

### Finding atom —— 照 Conventional Comments 結構

```
### <icon> [F<n>] <label> [(decoration)]: <subject 一行抓重點>
                                              ← 空行
<discussion:問題 / 建議>
```

- **atom 的 header 一律是 `###`**,掛在某個 `##` 節底下。三個 template 都同一深度,不因情境改變——`####` 沒有字級差,拿它當 finding 只是把層級做淺。
- **subject** 跟 label **同一行、冒號 `:` 接**(不是破折號),一句講清是什麼。subject 會渲染成標題,所以要短——細節寫進 discussion,不要塞進 subject 的括號裡。
- 要展開才 **空一行** 再寫 discussion;把 `問題:`(什麼壞了、誰承受、什麼條件)跟 `建議:`(修法 /
  選項)拆兩行,`file:line` 收在 `建議` 句尾,別揉成一句。
  - **先確認真的有選項再列。** (a) / (b) 只在兩條路導向**不同動作**時才列。若兩條路最後都要
    改同一處(差別只在改成什麼,而那個答案是確定的),那就是同一個結論——直接寫結論。列選單
    等於把判斷推回作者身上,是 hedge 的一種偽裝(見 `feedback_no_hedge`)。
  - **確實有多選項時要斷行**:每個選項**各自一行 / 一 bullet**、「我傾向 X + 理由」再另起一行;
    別用分號把 `(a)…;(b)…;傾向…` 串成一長行——擠成一團時人得自己拆才數得出有幾個選項。這是
    「一個獨立查核點 = 一行」在 discussion 內的延伸:每個選項就是一個獨立可選點。
- **trivial(nitpick / 小事)**:discussion 可縮成一行,但**標題仍然只放 subject**——
  說明與 `file:line` 寫在標題**下面**那一行。這是上面「subject 要短」的同一條規則,
  不是 nitpick 的例外。**對照物件是同一則 comment 裡最長的那個非 nitpick 標題**:
  超過它就是塞太多,數字元就查得出來,不必先察覺任何事。

- **Mechanism as picture, ask as prose.** 難點在**順序 / 時序 / 分支**(sequence、
  loop、race、swim-lane)時,把*機制*放進 fenced `text` codeblock(monospace,連簡
  單箭頭流也對齊);discussion 的 prose 只留給可行動的 `建議` / 選項。難點不在時序
  (nil-deref、常數錯、缺 error wrap)→ `問題` 寫一句散文,不畫圖。
  - **不用 blockquote**:codeblock 的 monospace 已把機制框成單位,blockquote 邊框
    會與 fence 互斥。
  - 單欄 / 線性箭頭流不需欄位對齊,CJK 安全;真 2D 多 lane 才要 lane 骨架維持全
    ASCII、中文註解擺箭頭右側(欄位內塞 CJK 會跨字型爆版)。

- **什麼進 `issue (non-blocking)`**:只收**具體 failure mode 或 ops risk**(API
  bump 靜默 no-op、無 event/metric 的 wedged 狀態、特定未來條件才咬的 guard)——
  不是 style / naming / 結構偏好。測試:講得出它防的情境嗎?「讀起來比較順」→ 丟掉。
- Post gate survivors —— 與上面 icon 表一致的完整清單:`issue (blocking)` / `issue
  (non-blocking)` / `nitpick` / `suggestion` / `question` / `note`。`praise` 併進 verdict
  行、不單獨成項。style / 臆測丟掉。空的 blocking-tier 是合理結果,仍要列有具體風險的
  non-blocking 項。

## A. Approve (no blocking findings / arc 終點)

```
LGTM 👍

<一行總判：對症的最小修正 / 方向正確，解在對的層級>

## Review recap

<一到兩句：這個 PR 解的問題 + 解法 + `file:line`。這是「根因對齊」，短到不需要自己的標題>

## Follow-up（非阻擋）

### <icon> <label>: <subject 一行>

問題：…
建議：… `file:line`

<收尾行：只在 Follow-up 非空時寫，說明「有這幾項但不擋」>
```

**兩個 `##` 節,finding 在 `###`。** 「根因對齊」只有一到兩句,不需要自己的標題,直接當 `## Review recap` 的內文;finding 放 `###` 才拿得到字級差(`####` 只有間距)。這個形狀跟 Template B 一致——**三個 template 的 finding 都在 `###`**。

**Follow-up 項不編 F-id**——A 是 arc 終點,這些項留給後續 PR,不會在這支 PR 再走一輪 carry forward(要編號的是 B / C,見下)。

沒有「驗證項目」/「測試 / 文件 / CI」節——查核結果本身構成 finding 就進 Follow-up,否則不寫(見 Conventions 的「只寫 review 的內容」)。Follow-up 為空時整節省略,收尾行也省,`LGTM 👍` + verdict 就是全部。

「根因對齊 / 修法」要是 **reviewer 自己的說法**,不是 PR 描述的改寫——它證明下判斷前讀懂了改動,approve 的重量建立在這上面。這是它跟「幫作者確認事項」的差別:前者是判斷的依據,後者是閘門的產物。

## B. Has findings (first review)

```
## Review recap

<一行總判：邏輯乾淨但有以下需調整>

### 🔴 [F1] issue (blocking): <subject 一行抓重點>

問題：<什麼壞了、誰承受、什麼條件下會發生;時序 / 流程 / loop 放進 codeblock(箭頭流 / swim-lane),把先後、handoff 畫出來>
建議：<修法> `file:line`

### 🟡 [F2] issue (non-blocking): <subject>

問題：<同上;時序放 codeblock>
建議：<修法> `file:line`

### 🔵 [F3] nitpick: <小問題,標題只放 subject>

<一句說明> `file:line`
```

B 沒有「根因對齊」節,也沒有 catch-all 的「另：」。前者因為 finding 本身就證明了讀懂——寫得出真的 blocking finding 不可能沒理解改動,而 request-changes 不像 approve 需要額外背書;後者因為 merge 衝突、rebase 狀態作者在 PR 頁面看得到,真正可 review 的點該帶 label 成為 finding。

**F-id 從第一輪就編。** 沒有 id 的第一輪,第二輪要 carry forward 時無從引用——等到 re-review 才補號,前一輪的項就會悄悄掉。

## C. Reply confirmation (re-review after author addressed comments)

```
## Review recap

前一輪 N 點：M 已解、K 待調整；新增 commit 一併看過。

### 逐點對照（對 commit 驗，非只看回覆）

- ✅ [F1] nitpick: `<sha>` 守住 <invariant> `file:line`
- ⚠️ [F2] issue (blocking): 回覆說 X，但 `<sha>` 只改表面，根因仍在 `file:line`
- ❌ [F3] note: 未處理 / 理解偏差 — <差在哪>

### 🔴 [F4] issue (blocking): <這輪 commit 帶進來的新發現>

問題：<什麼壞了、誰承受、什麼條件下會發生;時序放 codeblock>
建議：… `file:line`

總判：<全解 → 切 Template A 做全面 recap + approve；仍有 K 點 → 待下一輪，列出是哪幾點>
```

無新發現時,在「逐點對照」後一行明寫「新 commit 未引入新問題」,**不開空節**。

沒有常設的「一致性」行:修正沒帶到相關 test / doc / callsite 時,那本身就是一個 `⚠️` 或 `🔴` finding,寫進逐點對照或新發現;沒漏就不提。常設一行會複製「驗證項目」節的老問題——沒東西可寫時被填成「test 有同步」,那就只是「我看過了」。

## Multi-round composition（B / C / A 跨輪）

Review 是一條 arc,不是獨立快照。每個 re-review 輪是一則 comment,可同時帶三個 part,取這輪需要的:

- **已解(C-part)**:前輪 finding 已修 — icon 用狀態(✅/⚠️/❌)、label 退文字,引 `<sha>` + 守住的 invariant。
- **仍開放 / 新發現(B-part)**:前輪未結(從**任一**更早輪 carry forward,不只上一則)+ 本輪新發現,用 atom 格式(heading 帶嚴重度 icon + `label: subject`,空一行後接 問題 / 建議 + `file:line`)。
- **總判**:開放 = ∅ → 切 **Template A**(全面 recap + approve);否則「待下一輪」+ 列開放項 id。

用穩定 id(F1、F2…)跨輪追蹤,避免舊項悄悄掉。順序固定 **icon → `[F<n>]` → label**:icon 擺最前面當掃讀錨點,id 用方括號跟 label 分開。頂部可放一行 ledger:`累計 F1–F6:已解 5 / 開放 1(F5)`。

**終點規則**:arc 收在 A、不是 C。C 是中間態;「全部驗過、approve」的全面總結住在 A。

範例(混合輪,對應 `B → reply → B&C → reply → C` 的中段):

```
## Review recap

第 2 輪（B+C）— 累計 F1–F4：F1、F2 已解，F3 待調整，本輪新增 F4。

### 已解

- ✅ [F1] nitpick: `<sha>` 守住 <invariant> `file:line`
- ✅ [F2] note: `<sha>` 守住 <invariant> `file:line`

### ⚠️ [F3] issue (blocking): 部分 / 表面

回覆說 X，但 `<sha>` 只改表面，根因仍在 `file:line`

### 🔴 [F4] issue (blocking): <新發現 subject>

問題：<什麼壞了、誰承受、什麼條件下會發生;時序放 codeblock>
建議：… `file:line`

總判：F3、F4 未結 → 待下一輪。
```
