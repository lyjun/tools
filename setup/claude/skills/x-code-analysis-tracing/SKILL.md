---
name: x-code-analysis-tracing
description: 在分析 code 行為的「為什麼 X」「為何 X」「why does X」類問題,或分析 PR / issue 的 code-level root cause、設計 fix、review regression、靜態 trace 跨模組 code 行為時,強制先走 trace plan 釐清相關 code 上下文再 draw conclusion,避免基於 surface evidence 推測。也管修法排序前的消費者盤點,以及輸出格式 hygiene(ASCII diagram 必須 fenced code block)。聚焦靜態 code 閱讀;live 系統/環境 runtime 故障診斷(service 起不來、不通、狀態漂移)不在此列。
# opus:此 skill 在深度 root-cause 分析的 turn 內 inline 載入,宣告值若生效會直接決定
# 那段推理跑在哪個 model 上;降級損害的正是它要保護的對象。
# 生效與否看呼叫路徑(2026-09-06 於 v2.1.263 複驗,見 x-cc-config-guide):使用者打
# /x-code-analysis-tracing 開一輪會真的切換,回合中途被 Skill tool 載入則維持 session 的 model。
# 這支絕大多數是後者,所以保護實際來自 session 本身跑在 opus 上,不是來自這個宣告。
model: opus
---

# Code Analysis Tracing

收到分析 code/system 行為的請求時(典型訊號:使用者問「為什麼 X」「為何 X」「why does X」、PR root cause、issue regression、設計 fix、review 跨模組行為),**先走完 trace plan 才能 draw conclusion**。

Surface-evidence 推測(只看 error chain 字串、log timeline、symptom)是失誤的主要來源:基於現象推結論方向偏掉,使用者質疑後才回頭驗,等於浪費多輪。

## Trace Plan(mandatory before conclusion)

多數項目依任務情境挑選;**帶明確觸發點的項目(Side Effect Timing、Rendered Artifact vs Input)一旦觸發條件出現就必須執行,不受「看起來不相關」的篩選排除**。**結論必須 cite trace 結果**(file:line / grep 證據 / 函式 signature),不是 surface inference。

### 1. Symbol Ownership

該 ctx / error / state / channel 是誰建、誰修改、誰消費?

- ctx:是 fx lifecycle、parent ctx、`context.WithCancel` child、還是 server stopCtx?何時 cancel?
- 共享 state(ConfigMap、PVC file、global var):誰寫?誰讀?(哪一份是 authoritative 交給第 5 項,別在這裡用淺答案打發掉)
- 例:`Run(ctx context.Context)` 進來的 ctx 是哪一層 cancel?Grep `StartRunnables`、`fx.New`、`lifecycle.Append` 找呼叫點。

### 2. Error Wrap Chain

要用 `errors.Is(err, target)` 或 `errors.As(err, &target)` 之前,**必須先驗整條 chain**:

- 每層 wrap 是 `%w` 還是 `%v`?`%v` 斷 chain
- 自訂 error 類型有沒有實作 `Unwrap() error`?沒有也斷 chain
- 底層 sentinel 真的是 target?(e.g. `context.Canceled` vs `context.DeadlineExceeded`)
- Chain 任一層斷掉,`errors.Is` 等於 dead code

### 3. Stage Flow

跨 stage / 跨 path 的行為是否分支?單一現象可能對應多個觸發路徑:

- 例:升級流程有「firmware reboot path」(整機重啟,新 pod 接力 recovery)跟「pod restart path」(只換 platform-core pod,chart 已部署完成)— 中斷源頭、復原語意不同
- 例:同一 audit event 可能來自 `executeUpgrade` success tail、`reportHopFailure`、`Run/RecoverUpgrade` 後三個不同 emit 點 — 每個有自己的 ctx 跟 guard
- `grep` 所有 caller / emit 點,確認**這個現象屬於哪條 path**
- **對比兩條 path 行為差異時,每條 path 的 input data 也要 trace 到 producer**——producer 才是 invariant(sort 順序、state lifecycle、ctx ownership 等)建立的位置;分支內函式只是 consumer。只看分支內部容易得出對稱性錯覺(「branch A 做了 X,branch B 沒做」),但實際 invariant 可能在 producer 那端就建立了

### 4. Side Effect Timing

I/O、log、audit、metric 是 sync 還是 buffered?

- **觸發點(必跑,不是選配):症狀是「沒看到 log / audit / metric / 某個輸出」。** 這一項的結論是一句否定陳述(「timing 不是原因」),跟「根本沒問過」在文字上無法區分——所以它是最容易靜默略過的一項,要靠這個外顯症狀綁住
- `audit.Emit` 走 OTel batched send — pod 死太快 buffer 沒 flush,emit 看不到
- `log/slog` 透過 handler 可能也 buffered
- File write 是否 fsync?ConfigMap update 是否 strongly consistent?
- 觀察 timeline 之前必須先知道 emit 是否會被 grace-period 影響

### 5. State Source of Truth

多個地方記錄**同一份** state,哪個是 authoritative?哪些是 cache / mirror?

- 例:`arx-metadata.version`(ConfigMap)vs `upgrade-state` ConfigMap vs `/etc/arx-release`(host file)— 升級流程把不同層級 version 分散儲存,需 trace `SaveVersion`、`firmwareUpgrader` 等才能對應
- Conclusion 的依據必須是 source of truth,不是 mirror

### 6. Rendered Artifact vs Input

第 5 項是**同一份 state 存在多處**,這一項不同:**有東西讀這個檔、產出另一個檔或物件,而那個產出物才是真正在跑的**。這時 input 檔不是 mirror,是原料——template 會在它之上**追加**內容,所以「input 檔裡沒有 X」推不出「跑起來沒有 X」。

- **觸發點**:正要宣稱「跑著的東西目前的設定/狀態是 X」,而依據是一個會被別的東西讀進去、產出另一份檔案或 object 的檔案
- **適用範圍(不靠自我判斷)**:只有**部署後可能與 input 產生落差**的產出物適用——`deployments/*/values.yaml` → chart template → CR、`manifests/*.yaml` → toolkit generate → `release/manifest_*.yaml`、HelmRelease 的 `.spec.values` → helm merge → CR。**隨 build 同步重生的產出物不適用**:protobuf `.proto` → `.pb.go`、swagger 註解 → `docs/`、一般編譯輸出——它們與 input 在同一次 build 內必然同步,去讀產出物對問題沒有幫助
- **動作**:去讀產出物本身。`kubectl get <CR> -o yaml`、`helm get values --all` 或 release secret 解出來的 rendered manifest、`release/manifest_*.yaml`
- **停止條件**:結論引的是產出物的路徑或指令輸出,不是 input 檔的 `file:line`。兩邊不一致時**產出物勝**,而且那個不一致本身要寫進結論——它通常就是根因
- **拿不到產出物時的出口**(沒有 cluster 存取權、機器在別的網段、使用者已明講沒權限):不是停下來反覆要權限,也不是照樣引 input 檔下結論。做法是**在同一句話裡**帶上「依 input 檔推斷,未讀產出物」——把一個看不見的違規變成看得見的保留條款
- 實例:`opentelemetry-kube-stack/values.yaml` 把 `pipelines.metrics.receivers` 寫成只有 `otlp`,實際 CR 是 `["prometheus","otlp","host_metrics","k8s_cluster"]`。chart 依 `scrape_configs_file` 與 presets 往上加,清單減不掉。憑 values.yaml 斷言「已排除」,方向就整個偏掉

## 修法排序前先數消費者

這一節不在 Trace Plan 裡,因為它管的不是下結論之前的調查,而是**你可以把什麼叫做修法候選**——發生在分析結束、開始提修法的時刻。走完 Trace Plan 的人不會回頭掃那一節,所以它放在這裡。

**觸發點**:正要把幾個候選修法排順序,或正要寫出「這是根本修法」「主要修法是 X」「建議改 X」這類**指向某個修法**的句子。限定在修法語境——「建議你先讀這兩個檔」不算。

**動作**:把壞掉的那個東西的消費者列出來(grep callsite、查有幾個 metric / rule / 查詢在讀它),每個標「受影響 / 不受影響 / 未查」,並用**最便宜的一次量測**確認規模(`count(...)`、`grep -c`、callsite 數)。

**停止條件**:表上沒有「未查」;每個候選對照那張表,標出它落地之後**還有哪些消費者仍是壞的**。**還有剩的不得稱為「根本」或「主要修法」**。判準是修完之後剩下什麼,不是修好幾個——所以真的只有一個消費者時,修它就是根本修法,這條不會誤擋。

消費者跨越 grep 不到的範圍時(未 checkout 的 repo、動態 dispatch、外部服務的 generated client),窮舉本身不可能,合法的停止點是**明寫「已知 N 個為下界,無法窮舉」**,而不是把它們悄悄排除在清單外製造假完整感。

實例:`node_*` 有 381 個指標名,只有 storage 那條 PromQL 寫了 `max by (device, instance)` 而免疫。把「改那條 PromQL」排成主要修法,等於修唯一沒壞的那個,380 個照樣壞著。`count(node_memory_MemTotal_bytes)` 回 2 這一個指令就會把順序整個翻過來,而它一輪就跑得完。

## 禁忌

以下**措辭與引用形狀**都代表「未驗證的推測在替代分析」,應在出現前自我攔截:

- 「可能是 X」「應該是 X」「大概是 X」「推測是 X」「研判 X」「推斷 X」(沒附「需驗證: ...」)
- 「hiccup」「transient」「短暫不穩定」(替代 timing race / ctx ownership 分析)
- 「環境問題」「網路問題」(替代具體 trace 結果)
- **講「跑著的東西現在的設定/狀態是 X」,而依據是靜態來源**——不論它長成 `file:line`、commit SHA、PR 連結、拆到下一句的旁白,或是完全不附來源。這個組合本身就是違規,不用先察覺自己沒查。runtime 狀態的依據只能是**這次跑出來的**指令輸出;引 `MEMORY.md` 或前一個 session 的輸出不算,那是可能已經過期的記錄。方法見〈Rendered Artifact vs Input〉與它的「拿不到產出物時的出口」

### 第二次追問就換策略

收到**第二次**「為什麼 X」追問,代表前一輪推測使用者不認可。第二輪起必須換 verify-first 策略——不要再 elaborate hypothesis,先 grep / 讀程式碼 / asking for evidence(`kubectl describe pod`、`kubectl get events`、specific log path、source file path)。

## 輸出格式 Hygiene

跟 trace plan 同時檢查的 output formatting:

### ASCII Diagram 必須包 fenced code block

任何 box-drawing 字符(`─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ → ▼ ◄ ▶ ◀`)組成的 diagram,**必須**包在 ` ```text ` 或 ` ``` ` fenced code block 內。

GitHub markdown 渲染預設 proportional font,空格寬度不一致,monospace 對齊跑掉。Code fence 強制 monospace 才能維持對齊。

適用情境:PR comment、issue body、GitHub-rendered markdown docs、commit message body(部分 viewer 用 monospace)。

### 禁止雙欄並排 diagram,一律上下兩個 code block

中文字元在 monospace font 寬度 ≈ 2 個英文字元,但不同 font 渲染不一致(SF Mono、JetBrains Mono、Cascadia Code 等行為不同),雙欄並排 ASCII 的對齊在其中至少一種下會跑掉。

要並排呈現兩件事時,拆成上下兩個獨立 code block,各自單欄對齊。
