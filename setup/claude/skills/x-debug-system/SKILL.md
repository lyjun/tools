---
name: x-debug-system
description: >
  系統/環境 runtime debug —— device、network、systemd、service 在 live 環境出
  問題時(crash、不通、狀態漂移、起不來),到現場觀察(SSH / kubectl / journalctl /
  tcpdump)、隔離、實測驗證假設、修復。Trigger on: 系統層故障、live 環境異常、
  「X 在機器上壞了 / 不通 / 起不來」、device / network / systemd 問題、跨 service
  runtime 失敗需現場診斷。範圍是活系統現場 debug;純靜態 code 閱讀(理解既有行為、
  「為什麼這樣設計」)不在此列。
user-invocable: true
model: sonnet
---

# System / Runtime Debug

在 **live 系統 / 環境**出問題時(device、network、systemd、service runtime),到現場
觀察、隔離、實測、修復。對象是活系統的執行狀態,不是靜態 code。

## 雙軌原則(這支 skill 的核心)

兩個失敗模式方向相反,所以用兩條軌道各壓一個:

**軌一 — 紀律(壓住憑印象亂猜)**

沒收到真實證據前不下結論。具體紀律寫在下方 Methodology,精神是:先到現場收 live 證據、
按環境特性決定查的順序、結論必須 cite 直接證據。

**軌二 — Escape hatch(允許在死路上誠實換方向)**

走完軌一仍找不到根因時,或照根因實作的修正沒有消除症狀時,**明說沒找到 / 沒修好**,然後換路
—— 而不是硬湊一個結論交差、或在沒修好的修正上再疊一個。詳見
最後的 [Escape Hatch](#escape-hatch) 段落。沒找到就說沒找到,是這支 skill 比任何
checklist 都重要的一條。

---

## Methodology

整體遵循 **Observe → Isolate → Hypothesize → Experiment**。簡單故障直接套用推理,
跨層 / 根因不明則走下方完整流程。

### 1. Observe — 到現場收 live 證據

- **描述點名了與系統互動的 app 時,上主機前先產出檢查表**:讀 app 原始碼(README / docs 只用來找入口),
  在回覆裡寫出下表。表寫出來之前,主線與任何 subagent 都不 SSH 到主機。

  | 站 | 事件 | app 依據 file:line | 這站對此事件留紀錄的 file:line(沒有就寫「無」) | 直接觀察方式 | 結果 |

  「事件」逐列列出 app 判定成功 / 失敗會經過的每一件事(例:收到查詢、送出回應、丟包),一列一個。
  結果欄只能填:pass / fail / 看不到。任何一列填 pass 都要附此事件確實發生的直接輸出(例:tcpdump 抓到封包、
  防火牆計數器增加、log 印出這件事本身);錯誤 log 沒出現、service active、介面 up 一律不算,不論紀錄欄填什麼。
  結果為「看不到」的列,在 Isolate 的消去法、任何摘要與 Debug Report 裡都只能寫「未驗證」,不得寫成正常或已排除。
  app 原始碼位置(主線與任何 subagent 都適用,含 Step 2 的 Agent B;B 的 prompt 只能帶已由使用者或
  memory 確認的路徑,關鍵字搜尋不算確認位置):使用者給了路徑就用;沒給就一律查 memory 有沒有這個 app
  的原始碼位置記錄,不憑印象或目錄名猜。有記錄就照記錄讀並說明讀的是哪些目錄;沒有記錄,先問使用者,問到的位置寫進 memory。
- **先 snapshot,不靠想像**:一次收齊相關的真實狀態 —— `systemctl status` / `journalctl`、
  網路(`ip addr`、`ip route`、`ss`、`tcpdump`)、mount、container(`crictl`/`docker ps`)、
  `dmesg` / kernel log。不要憑「應該是這樣」補空白
- **進 Hypothesize 之前，先有一條重現指令**：一條本 session 已經實跑過、會在這個症狀上失敗、
  修好後會通過的指令（測試、`curl`、在裝置上跑的迴圈腳本），指令與輸出原文貼進回覆。Experiment
  驗修正跑這條；每個假設至少有一項 evidence 寫成「動了 X 之後這條指令會 ___」，其餘照下面
  Hypothesize 的現場觀察。建不出來時寫「無重現指令：試過 `<指令>` → `<輸出，未呈現症狀>`」，
  或貼出只發生過一次的證據（那次的 log 與時間戳）——一個詞的原因（「偶發」）不算。重現要重開機、
  要動設定的，不是建不出來，是「重現指令待使用者同意後執行」。這句要寫在第一個假設之前，寫在
  後面就是先猜了才補理由。沒有重現指令時，驗修正改成：重建當初發生的條件，跑監看指令（例如
  `journalctl -f -u <unit>`），寫明觀察多久、症狀有沒有再出現
- **Triage first**:先界定影響範圍。是整個 service down,還是只是某個 probe 回報失敗?
  第一次發生?反覆?最近改了什麼?——context 不明先問
- **Correlation ≠ causation**:時間相近不等於因果。主張「A 導致 B」要有直接證據(syscall、
  封包、log 明確連結 A → B),不是「剛好同時發生」
- **No hiding errors**:禁止 `2>/dev/null || true` 把問題藏掉

### 2. Isolate — 縮範圍

- **Infrastructure before application**:基礎設施先於應用。網路 / DNS / 權限 / 磁碟 / 
  systemd 依賴沒問題,才往 app 層查。底層壞掉時別在 app log 上浪費回合
- 最小化:先確認「什麼**不是**問題」,用消去法排除候選再聚焦剩餘
- **有正常的對照時，好壞兩邊跑同一組指令再逐項比**:同機種的另一台、同一台改動前的狀態、同
  service 的另一個 pod。指令是 Observe 那份 snapshot 的全組，不是只挑懷疑的那幾條——沒收的差異
  看不見。兩邊輸出的差異逐項列出(時間戳、PID 這類必然不同的欄位可以略過，寫明略過了哪些),
  每項標「已排除／待驗」。「已排除」的依據要是實測:把那一項對齊後重跑、或貼出顯示它無關的輸出;
  只有推理的一律標待驗——不先判定哪項「不可能有關」。沒有對照時寫「無對照：<原因>」(例:同機種的全都壞了、拿不到另一台的存取權)——記憶中的正常值、文件寫的預設值都不算對照,那是
  「應該是這樣」,不是量到的
- **兩個東西靠名字分不出來時,用行為矩陣分,不要靠名字猜**:同一個 Subject DN 的兩張根憑證、
  同名的兩條中繼、同名變數、同 tag 的兩個 image——把 N 個候選 × M 個操作全跑一遍,看哪些組合
  成立。觸發點是外顯的:我正要用「名字一樣所以是同一個」或「名字不一樣所以不是」當論據
- **拿 ARP、MAC 比對、WoL 下結論前,先確認自己站在目標的網段上**:`route -n get <target>`(Linux 用
  `ip route get <target>`)的出口要是直連介面,不是經 `gateway`。ARP 只記得自己所在網段的鄰居,目標在別的
  網段時怎麼 ping 都不會出現;WoL 的 magic packet 是 L2 廣播,從別的網段送等於沒送,看起來跟主機不理會一模一樣。這時查不到量到的是自己站的位置,
  不是機器不在——徵兆是同網段**一台都沒列出來**,但什麼都不報錯。(例:Mac 在 192.168.1.x、目標在
  192.168.5.x,兩輪 ping 掃描後 grep ARP 都是空的。)出口是 gateway 時,從主機清單找一台在目標網段上的主機
  做探測,輸出要印出那台主機自己在該網段的位址,讓讀者看得出探測點站對了;在那裡 `ip neigh show <target>`
  三次 ping 後仍是空的,才是真的查不到
- **Multi-service call chain**:跨 service 的 gRPC / HTTP 故障,從 caller 到 callee 逐層
  驗證每層 log,不要跳過中間 proxy。proxy 回應時間極短(µs)通常代表它自己回了錯,沒轉發

### 3. Hypothesize — 提假設

- 每個假設講清楚:**what** 你預期、**why**、**what evidence** 會證實或否證
- **證據分級**:直接證據(log 點名 cause、封包明確) → 提修復;間接證據(狀態異常、時間相近)
  → 跨來源交叉驗證後才提;證據不足 → 回 Observe / Isolate,不提
- **禁無驗證搪塞**:以下措辭代表「推測在替代分析」,出現前自我攔截 ——
  「應該是 X」「可能是 X」(沒附「需驗證: ...」)、「hiccup / transient / 短暫不穩」、
  「環境問題 / 網路問題」(沒有具體 trace 結果)
- **5 Whys**:第一個答案很少是 root cause。每層都問 why,每層都要直接證據。停止條件:
  修這層能防止復發
- **錯誤訊息給了多個可能時,到現場逐一排除,不要從 hint 文字挑一個順眼的**。工具列舉可能原因
  是因為它自己分不出來;挑一個當假設等於把工具的不確定性當成已知。逐項寫出「這一項要看什麼才
  能排除」,再去現場看,排不掉的才是候選

### 4. Experiment — live 驗證

- **真實驗證,不是 mock**:到實際系統上跑(toggle 設定、重啟單一元件、重放封包),觀察行為
- **One variable at a time**:一次只動一個變數
- **Disprove first**:優先做能否證假設的測試,不是只做能證實的
- 腳本從簡單開始(≤30 行)逐步加複雜度

---

## Step 0: Triage

- **單點、現象明確指出位置**(單一 service、明確 error) → 跳過 parallel,直接套 Methodology
  推理(Observe 現場 → Hypothesize → Experiment 驗證),報告 root cause + 修復方案
- **跨層 / 多元件 / 根因不明** → 進 Step 1 完整流程
- **疑似 regression**(最近變更後才壞) → 完整流程,並啟用 Step 2 的變更歷史調查

## Step 1: Parse scope

從描述中抽出:**症狀**(什麼行為不符預期)、**已知相關元件 / 主機 / 路徑**、
**關鍵字**(error message、unit name、IP、port)。整理成簡短摘要,作為調查起點。

## Step 2: 平行收集證據(視情況)

環境 debug 多半是 **live 系統觀察**(SSH / kubectl / journalctl),不是讀 code —— 簡單
故障一條線查到底即可,**不需**動用 parallel agents。

只有當調查同時跨 **live 環境 + 程式碼**、或跨多主機 / 多元件、單線查太慢時,才在**單一訊息**
平行啟動 2-3 個 Agent subagent:
(Observe 第一條的檢查表適用時例外:A 與主線 SSH 都等表寫完才開始,不與 B 同一則訊息發出)

| Agent | 任務 | 策略 |
|-------|------|------|
| A: 現場狀態 | 收集 live 系統證據 | SSH 跑 snapshot 指令(systemctl / journalctl / ip / ss / dmesg) |
| B: Code / 設定 | 對應到程式碼或設定的相關邏輯 | `grep` 相關 unit / handler / config key → Read |
| C: 變更歷史(regression 才開) | 找近期相關變更 | `git log -p` 相關檔案、最近部署 / 設定變更 |

讀 code 的 agent 用 `subagent_type: Explore`;純收 live 證據的可由主線直接 SSH 跑(不必開 agent)。
每個 agent 的 prompt 須含:問題描述、起點關鍵字、輸出要求(證據 + file:line / 指令輸出 + 結論)。

## Step 3: Synthesize

所有發現依 Methodology 驗證證據強度後彙整。簡單案例(指向單一明確原因)直接說原因 + 修復方案,
確認後修。否則輸出結構化報告:

```markdown
## Debug Report

### 問題
<原始症狀>

### 現場證據
<關鍵 log / 指令輸出 / 封包,標明來源主機與時間>

### 根因
<call chain / 狀態流 / 變更,如何連到 root cause —— 每步附直接證據>

### 建議方案
| | 方案 A | 方案 B |
|---|--------|--------|
| 描述 / 優點 / 缺點 / 影響 | ... | ... |

### 影響範圍
- 需修改: ...
- 可能受影響: ...
```

## Step 4: User decision

用 AskUserQuestion 讓使用者選方案(或提其他想法),確認後才實作。實作後驗證症狀沒消除,
走 Escape Hatch 的第二個入口。

## Step 5: 留存非顯然的發現

修復確認有效後,若根因屬非顯然的領域知識(service 之間的互動、特定環境的陷阱、
排除掉的錯誤方向),依一般 memory 慣例寫成一則 project 或 reference memory。
判準是**下次有人撞到同樣症狀,這則能不能讓他少走一段**——不是「這次查得辛不辛苦」。

顯然的原因(打錯字、少設環境變數、密碼錯)、以及一次性的人為失誤,不必記。

---

## Escape Hatch

**第一個入口:找不到根因。** 軌一走完(現場收了證據、排除了候選、提的假設都被實測否證)仍找不到根因時:

1. **誠實宣告**:明說「已驗證排除 X / Y / Z,目前無直接證據指向 root cause」。**不准**為了
   給答案硬湊一個結論 —— 沒找到就說沒找到
2. **才允許換路**(以下任一):
   - 擴大 Observe 範圍(先前沒收的層:更上游的網路、更早的 boot log、相鄰主機)
   - 換假設角度(原本盯 app,改查 kernel / 硬體 / 時序 race)
   - 回頭向使用者要更多現場資料或重現步驟
   - 提出先前沒想到的發散方向,標明這是待驗證的猜測

換路後回到軌一重新驗證 —— escape hatch 是「誠實承認 + 有依據地換方向」,不是「放棄紀律開始亂猜」。

**第二個入口:修正沒修好。** 任何修正(含 Step 0 / Step 3 簡單案例直接做的)實作後,驗證時症狀還在:

1. 那個根因判斷已被實測推翻。明說「修正 <N>/3:<改了什麼> → 驗證 <指令> 結果 <輸出>,症狀仍在」,
   把這次修正與結果記進現場證據,回到軌一重新 Observe —— 不在它上面疊第二個修正
2. 同一個症狀第 3 個修正仍失敗時停下,不提第 4 個。跟使用者討論的是做法本身(這條路線、這個元件
   該不該這樣用),附上三次修正各自推翻了什麼

## 注意事項

- parallel agents 只在跨層 / 多主機 / 單線太慢時才用;簡單故障別過度動用
- Agent 必須同一訊息平行發,不可串行
- 報告控制在合理長度
- 動手修復前先定位 root cause;確證據不足時走 Escape Hatch,不要在無證據下實作;修了沒好也走 Escape Hatch
