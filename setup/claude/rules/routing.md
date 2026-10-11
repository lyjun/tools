# Routing

This file documents the two mechanisms of skill discovery:

- **Description-time matching** (reactive): the main agent matches skill descriptions against user messages and loads the skill on hit
- **First-move guard** (proactive): some skills must load before the AI acts; description matching is too late (the signal is encoded in environment state, or the task's nature inherently surfaces it too late)

## Description-time matching policy

Before starting any domain-specific operation (infrastructure, cloud, product-specific tooling), or writing code that a standards skill governs, scan the available-skills list for a description that matches the current context and load the matching skill. Triggers include:

- Remote host credentials supplied (SSH password, host IP)
- Product-specific domains in commands (e.g. `ardge.xyz`, known service names)
- Sustained use of a specific stack across multiple turns (kubectl, flux, helm). **Two consecutive turns invoking the same stack is enough — do not wait for "I obviously need it."**
- About to create or modify a `.go` or `.proto` file, an HTTP handler / API request-response schema, or a Helm chart → load `x-coding-standards` **before the first edit**, small edits included. Writing the code first and comparing against the standards afterwards produces a rewrite, not a review.

The available-skills list is not the whole set: a repo's own skills live in `<repo>/.claude/skills/` and may not be listed. Before producing an artifact whose format that repo owns (an openspec change, a repo-specific document), `ls` that directory first.

Concrete stack → skill mappings live in Section B; consult that table the first time any matching command appears, not after a few turns of improvisation.

## A: First-move guard loading rules (must)

### First-move guard criteria

A skill enters this section if it meets any of:

1. AI may damage the environment before the skill triggers (e.g., editing the wrong container, deleting a worktree by mistake)
2. The operation requires the skill's preflight checks to execute correctly
3. Description routing has insufficient hit rate for the scenario (observed undertriggering)

### Loading semantics

- After loading, read the entire SKILL.md (not just the description) and apply its content — walkthrough for procedural skills, relevant sections for reference skills
- When multiple skills match simultaneously (e.g., `x-worktree` + devcontainer), **load all of them** and walk through each
- "Load immediately" means literally: invoke `Skill(<name>)` the moment the trigger hits. Do not defer with excuses like "still analyzing", "let me look first", "wait until something destructive", or "just reading files doesn't count". The trigger is **scenario hit**, not **whether the next action is destructive**

## B: First-move guard → skill mapping (refer)

When any of the following scenarios occurs, load the corresponding skill. **When multiple scenarios match simultaneously, every one must be handled in subsequent operations** — never pick a single scenario as the sole basis.

### x-environments

- Project directory contains `.devcontainer/`
- User references a remote host by alias (e.g., 「連到 dev」, 「登入開發機」), **even without IP/credentials**
- User asks to SSH into a host, including by account name (e.g. 「以 ardge 帳號 SSH」, "SSH as ardge", "ssh with the ardge account") — the account/login phrasing counts even when no alias or IP is given
- Other non-local execution environments (VM, cloud shell)

### x-worktree

- About to create a worktree (including colloquial synonyms: "issue folder", 「issue 目錄」, 「幫我開一個 issue」, all pointing to the same action)
- cwd is under `<ardge-workspace>/worktree/` (including subdirectories)
- About to clean up a completed worktree
- Cross-repo worktree operations
- About to perform mutating operations (commit / push / rebase / amend) on a non-default branch in the main clone (`<ardge-workspace>/<repo>/`, not a worktree path)

The last item does not trigger for read-only commands like `git status` / `git log` / `git diff` / `git show`. The judgment basis is **whether the main clone's branch state will be mutated**.

### x-git-ops

- Currently on `main` / `master` / `develop` / `release/*` branch and about to modify files
- About to rewrite history or force-update a ref on **any** branch, feature branches included: `rebase` / `amend` / `squash` / `reset --hard` / force-push

Read-only commands like `git status` / `git log` / `git diff` do not trigger. The first bullet's basis is **about to modify protected-branch files**, not "touching git in any form". For the second, branch protection is irrelevant: the skill's preflight (`references/workflow.md` 的 backup tag) only works if it runs before the rewrite. `cherry-pick` is not on the list.

### arx-groundwork

即將動工，而「什麼是對的」的依據還沒被寫下來：

- 使用者給了 `ardge-labs/ardge-project-issues`（規格單／需求單）或 `ardge-labs/ARX-bug`（bug 單）的 issue 連結或編號，並要求規劃 / 實作 / 拆單 / 估範圍
- issue body 有 `## Specification` 欄，或有 parent / sub-issue / relation，或內文寫著關聯的 issue URL 或 `#nnn`
- 即將替 `PLAN.md` 的〈判準出處〉欄填值，或那欄是空的
- 即將對一個沒有規格文件的功能做建模、命名、跨 repo 改動，或對外部規格（IPMI、sysfs、proto 契約、kernel 行為、對端協定）下判斷
- 任務是 per-machine / per-product 查找表這一類（硬體佈局、sensor 對照、port 命名、機種能力表）。判準是「同一份程式碼要依機種讀不同的值」
- bug(不論有沒有開單)的根因已確認、即將為修根因而改 code(診斷用的插樁不算)——包含之後的輪次只說「修吧」、沒有再貼 issue 編號

**Trigger timing**: 開始讀 code 之前,不是讀完之後。bug 例外(不論有沒有開單):觸發點是根因確認後、為修根因而改 code 之前。第三條(〈判準出處〉欄)是補救入口——已經開工才想到時仍要載。第一條的「規劃 / 拆單 / 估範圍」與第三條都同時命中 `x-plan`,兩支都載,順序是 groundwork 先。

Does not trigger:

- 純查詢(「這個欄位在哪」、issue 內容是什麼)——沒有要動工
- 單檔的既知修正,根因與正確行為都已確認(bug 除外,不論有沒有開單:根因確認不等於正確行為確認,照上面 bug 那條觸發)
- 純 review 別人的改動——判準來自那份 PR 自己的敘述與 code,不是開工前的地形
- bug 單只要求查原因(「查一下」「為什麼壞」「找原因」),還沒要改 code——這一趟走 `x-debug-system` / `x-code-analysis-tracing`。根因找到、要動手修時才觸發,那時第二條的關聯回溯照做

Boundary with `x-code-analysis-tracing`: 那支解釋**既有行為為什麼是這樣**,這支為**即將寫的東西**建立判準。兩支都命中時都載——先 groundwork 釘住判準,再用 trace 紀律讀 code。bug 單例外:先 trace 找根因,要改 code 時才載這支。

### x-design-dialogue

一個決定該由使用者拍板，而手上沒有任何文件能回答它：

- 要做的事沒有規格,或規格在某一點沒寫清楚,而那一點是產品行為、介面形狀、命名、範圍取捨、完成判準
- 使用者說「討論一下」「你覺得怎麼做」「先別動手,先談」
- 需求只有一句話,讀 code 也答不出「做到什麼程度算完成」

**Trigger timing**: 提出第一個做法之前。已經提了才想到時仍要載——後面那句同意的門檻還沒過。

Does not trigger:

- 純查詢、單輪就答完的閱讀
- 根因與正確行為都已確認的修正
- 使用者已經給了做法、只要求執行

Boundary with `arx-groundwork`: 命中 arx-groundwork 任一觸發條件時(有 ardge issue,或沒有規格而要建模、命名、跨 repo 改動)先載 groundwork,它在規格缺口處把這支當步驟呼叫;兩支都不命中的討論(例如調整 skill 或 rule 的做法)直接載這支。

### x-plan

判準已經釘好,要開始把工作拆成項目或動手寫 code:

- 使用者說「開始做」「動工」「規劃」「拆一下」「怎麼分階段」「先做哪個」
- 使用者給了 issue 連結或一段需求敘述並要求規劃——這一條同時命中 `arx-groundwork`,兩支都載;釘完判準不算做完,拆單是另一半
- 即將寫 `PLAN.md` 的項目或日誌(建立 `PLAN.md` 這件事同時命中 `arx-groundwork`,兩支都載)
- 規劃階段就要決定跨 repo 的合併順序:哪個 repo 先合、下游何時 repoint
- 一個改動會動到兩個以上獨立子系統,或兩個以上 repo
- 接手一個已經有 `PLAN.md` 的 issue

**Trigger timing**: 寫第一行 code 之前。

Does not trigger:

- 單檔單函式的既知修正
- 單輪就答完的查詢與閱讀。**跨多輪的根因分析、修法評估不在此列**
- review 別人的 PR——檔案數只算自己即將動的檔
- 同一個機械變換套用到 N 個檔且彼此無依賴順序(rename、版號 bump、格式化)
- `PLAN.md` 的項目已存在,而正在做的是其中某一項、動到的檔沒超出該項〈動到的檔〉;超出就重新觸發

Boundary with `arx-groundwork`: 那支管**開工前**「什麼是對的」的判準,產出判準檔;這支管**判準已定之後**的拆單、切片與執行紀錄,產出 `PLAN.md`。同時命中時先 groundwork——判準已定時那趟只是確認判準檔的版本仍成立,不重跑。

### x-code-analysis-tracing

- User asks behavioral "why" questions about code/system: 「為什麼 X」, 「為何 X」, "why does X", "why is X", 「X 為何會失敗」, 「X 怎麼會...」
- Analyzing PR / issue code-level root cause, regression origin (含 user 直接給 issue/PR link + 要「分析」/「trace」/「結論」/「原因」, 即使沒明顯 why 字眼) — but a live runtime failure described in the issue routes to x-debug-system (see "Does not trigger" below)
- Causal analysis before designing fix / refactor (「這個 helper 該抽出來嗎」, 「這條 path 為何沒 cover」)
- Writing conclusions about cross-module behavior (cross-package, cross-service, cross-stage)

**Trigger timing**: the moment analysis begins, **before read / grep / drawing conclusions**.

Does not trigger:

- Pure lookup (「這個函式在哪」, "show me X") — no conclusion drawing involved
- Pure implementation request (「實作 X」) — root cause is known, tracing unnecessary
- User explicitly says 「直接做、不用解釋」
- Live system / runtime failure needing on-site diagnosis (service down, network unreachable, systemd unit failed, state drifted) → x-debug-system, **even when the user gives an issue / PR / bug link**

### x-debug-system

A live system / environment is misbehaving and the next step is hands-on diagnosis on the running system (not reading code to understand design):

- A device / host / service is broken at runtime: crashed, unreachable, won't start, state drifted (「X 在機器上壞了 / 不通 / 起不來」, service failed, network down, systemd unit failed)
- network / DNS / routing / systemd / mount / kernel-level symptoms needing on-site observation (SSH, journalctl, `ip`, `ss`, tcpdump, dmesg)
- cross-service runtime failure that needs live evidence from each hop, not just static code reading
- suspected regression where a deployed / config change broke a running system

**Trigger timing**: the moment hands-on diagnosis of a live failure begins — before guessing a cause or drawing conclusions without on-site evidence.

Boundary with `x-code-analysis-tracing`: 純讀 code 理解既有行為 / 「為什麼這樣設計」 / 靜態 root-cause 分析 → tracing;live 系統現場故障診斷 → x-debug-system。兩者都需要時(現象在環境、根因可能在 code),先 x-debug-system 收現場證據,再用 trace 紀律讀相關 code。需求描述點名了一個與系統互動的 app / client(Finder、web UI、CLI、另一個服務)時,順序改為:先讀該 app 的互動機制與成功 / 失敗判定,據此列出系統端的檢查點,再上現場 debug 與 trace 系統 code。觸發看的是描述裡有沒有這個 app,不是看現場的結果。

Boundary with `arx-cluster-ops`: ARX k3s cluster 內部故障(flux / pod / HelmRelease / upgrade)→ arx-cluster-ops;非 cluster 的系統層(device / network / systemd / host service)→ x-debug-system。

### x-cc-config-guide

- Creating or modifying any `~/.claude/skills/*/SKILL.md` (frontmatter, description, content structure)
- Adding, restructuring, or removing files under `~/.claude/rules/`
- Editing `MEMORY.md` or memory entries under `~/.claude/projects/*/memory/`
- Discussing whether a piece of knowledge belongs in rule vs skill vs memory
- Evaluating whether to enable/disable a plugin

`~/.claude/settings.json` changes are out of scope — handled by the `update-config` skill.

### arx-cluster-ops

About to perform any mutating operation against an ARX k3s cluster on an ARX host (anywhere in the office LAN `192.168.4.0/22`, i.e. `192.168.4.*`–`192.168.7.*`: static-IP hosts sit on `192.168.6.*`, DHCP ones elsewhere such as `192.168.5.*`; or any `~/.config/arx/hosts.yaml`-listed host):

- `kubectl` mutating verbs (`rollout` / `apply` / `patch` / `delete` / `edit` / `create` / `annotate` / `label` / `set image` / `scale`)
- `flux` any subcommand (`reconcile` / `suspend` / `resume` / `create` / `delete`)
- `helm` mutating (`install` / `upgrade` / `rollback` / `uninstall`)
- `k3s ctr` any image / container / namespace operation
- `nerdctl` (image `load` / `import` / `tag` / `push`)
- Editing `/etc/rancher/k3s/registries.yaml` or other k3s host config
- Restoring / reverting / rolling back cluster state after a test deploy
- Diagnosing pod / service / HelmRelease anomalies on ARX cluster (CrashLoopBackOff, Suspended, Failed, drift) when the next step is to mutate state

Read-only does not trigger: `kubectl get / logs / describe`, `flux get`, `helm get values / list`, `k3s ctr images ls`, `nerdctl images`. The judgment basis is **whether the cluster state will be mutated** — the moment the planned next step is to change something, the skill must already be loaded.

### x-pr-review

- About to review someone else's PR, or produce / post any PR-review output (findings report or PR comment)
- **Delegation does not exempt**: if any part of the finding-gathering is delegated to a sub-agent, the main thread still loads x-pr-review for the shared output model — sub-agents return findings, not the presentation format. Load `references/publish-format.md` before posting.

**Trigger timing**: the moment you start producing review output (findings report or comment), not merely reading a diff. Pure "explain what this PR does" without a review verdict does not trigger.
