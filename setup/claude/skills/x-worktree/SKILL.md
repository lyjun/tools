---
name: x-worktree
description: Procedural walkthrough for git worktree workflows in this workspace. Use when creating a new worktree (git worktree add, also phrased colloquially as "issue folder", "issue 目錄", "幫我開一個 issue"), splitting one spec into several PRs on the same repo so a second branch is needed alongside an existing worktree, checking out someone else's PR branch to push fixes onto it during a review (「幫他改」「直接改他的 PR」), working under <workspace>/worktree/, cleaning up a worktree (after PR merge, or after pushing to someone else's PR), or any cross-repo worktree operation. Covers directory layout, branch naming rules, choosing the base branch, and cleanup including devcontainer teardown.
model: haiku
---

# Worktree Workflow

每個觸發場景下都必須依本 skill 走完對應 section 的 checklist，不得跳步、不得只取單一段落作為依據。歷史 systemic 失誤源：

- Branch name 帶 issue number（漏看「`<issue-slug>` 與 branch name 無關」條款）
- Cleanup 漏 stop devcontainer（造成 docker mount 持續佔住 worktree path）
- Worktree session 中 rebuild 失敗未走 recovery 路徑

## 目錄結構

使用者以 git worktree 進行開發時，目錄結構為：

```
<ardge-workspace>/worktree/<issue-slug>/<repo-name>/
```

- `<ardge-workspace>`：ardge 專案的根目錄（如 `~/Desktop/Workspace/ardge`），即 main repo 的上層
- `<issue-slug>`：`<prefix><number>-<description>`，**與 branch name 無關**。全用 kebab-case，不混用底線。

  前綴記的是**這件工作從哪裡進來的**，讓 `ls` 一眼分得出「我自己開的」「規格單來的」「bug 單來的」。判定看兩件事：使用者給的 issue URL 落在哪個 repo，以及那張單有沒有指向一份規格（body 的 `## Specification` 欄，或內文寫明的規格 md 路徑）。第二件事要讀 body，`gh issue view <n> --repo <repo> --json body` 一次就夠。

  | 使用者給的來源 | prefix | number 取哪一個 |
  | --- | --- | --- |
  | `github.com/ardge-labs/ARX-bug/issues/N` | `bug-` | 上游那張 bug 單的 `N` |
  | `github.com/ardge-labs/ardge-project-issues/issues/N`（規格單與需求單都算） | `spec-` | 上游那張單的 `N` |
  | 實作 repo 自己開的單（`arx-platform-*`、`arx-os-installer` 等），而它指向一份規格，且 body 有 `Parent: ardge-labs/ardge-project-issues#M` | `spec-` | Parent 的 `M` |
  | 同上，但沒有 Parent（規格只是一份 md 檔，沒有自己的號） | `spec-` | 那張實作單的 `N` |
  | 實作 repo 自己開的單，沒有指向任何規格 | `issue-` | 那張工作單的 `N` |
  | 完全沒有 issue | 無前綴，直接用描述 | 無（如 `refactor-auth-middleware`） |
  | review 別人的 PR 並代改（見〈代改別人 PR 的 branch〉） | `review-pr-` | 那個 PR 的編號，不看它連到哪張 issue（如 `review-pr-240-account-sync-docs`） |

  `review-pr-` 是給人看的提醒：這個目錄掛的是別人的 branch，遠端那條不歸我管。它不參與任何判斷——清理時刪不刪遠端由〈清理流程〉step 7 查 PR 作者決定，目錄名打錯也不會因此誤刪。

  - **有上游單時號碼取上游那張，不取自己開的實作單**——實作單會為了拆 PR 再開好幾張，上游那張才是這個 issue folder 從頭到尾唯一不變的東西。實作單的 URL 寫進 `PLAN.md` 的出處欄；反過來，前綴是 `spec-` 而號碼取自實作單時（上表「沒有 Parent」那一列），要把規格檔路徑寫進 `PLAN.md` 出處欄，否則之後回溯不到判準
  - **只認直接指向規格，不追第二跳**：一張實作單只寫著「規格以 `#112` 為準」而規格在 `#112` 那張單上時，這張走 `issue-`。認間接的話回溯鏈上每張單都會變成 `spec-`，前綴就沒有分辨力了——跟下面 bug 贏 spec 是同一個理由。實例：`arx-os-installer#184` 指向同 repo 的 `#112`，判 `issue-184-`
  - **`ardge-project-issues` 的需求單也走 `spec-`**：前綴分的是「上游交下來的」與「我自己開的」，需求單屬前者。它與規格單的差別記在 `PLAN.md` 的出處欄，不由目錄名承擔
  - **bug 與 spec 同時命中走 `bug-`**，兩種形狀都算：同一張 bug 單回溯到某份規格，以及同一個 issue folder 底下 repo A 對到 bug 單、repo B 對到規格單。bug 單幾乎一定回溯得到規格，讓 spec 贏的話所有 bug 都會變成 `spec-`，前綴就沒有分辨力了。回溯到的那份規格照樣寫進 `PLAN.md`，不影響判準
  - **多張上游單同根因 → 號碼並列**：`bug-664-671-nodeip-drift`
  - **既有目錄不因為這條規則改名**：`git worktree move` 動得了路徑，但會抽掉正在跑的 devcontainer 掛載。新開的才套。所以 `worktree/` 底下較早建立的目錄是 `issue-` 開頭，那是舊規則的產物，不是這張表的反例——下面那個 `<repo-name>_<task>` 的範例用的也是既有目錄
- `<repo-name>`：要操作的 repo 名稱。同一個 repo 在這個 issue 底下要開第二條以上的 branch 時（一份 spec 拆成多個 PR），第二個之後的目錄命名為 `<repo-name>_<task>`：
  - `<repo-name>` 與 `<task>` 之間用底線，理由是 `ls` 的可讀性：repo 名本身多半含連字號，兩邊都用連字號時斷點落在哪要用猜的
  - `<task>` 本身仍是 kebab-case，寫的是這一刀在做什麼，不是 branch name 也不是 PR 編號——branch 會改名與 rebase，PR 編號在建目錄的當下還不存在
  - 第一個目錄維持不帶後綴，已經建好的不為了對稱改名：`git worktree move` 動得了路徑，但會抽掉正在跑的 devcontainer 掛載

  例：

  ```
  issue-112-raid1-system-disk/        # 既有目錄，建於前綴規則之前；照今天的表它是 spec-
  ├── arx-platform-manager
  ├── arx-platform-manager_nic-infor
  └── arx-platform-manager_init-disk
  ```

- 同一 issue folder 下可能包含多個 repo（跨 repo 的相關修改），也可能包含同一個 repo 的多個目錄（一份 spec 拆成多個 PR）

## 建立流程

0. **決定 `<issue-slug>`**：依〈目錄結構〉的前綴表，把使用者給的 issue URL 對到 `bug-` / `spec-` / `issue-` / 無前綴。使用者沒給 URL 就先問是哪一張單——前綴猜不出來，而目錄建好之後改名會抽掉 devcontainer 掛載。**要改的是別人 PR 的 branch** → 前綴 `review-pr-`，下面 step 1、2、4、6 改走〈代改別人 PR 的 branch〉；step 3 只用來決定 `<dir-name>`，base 不適用；其餘照常
1. 在 main repo 先更新 develop：`git -C <ardge-workspace>/<repo-name> pull origin develop`
2. 決定 branch name（**checkpoint：與目錄 slug 切開**）：
   - 依 Git Flow branch naming 規範：prefix 必須是 `feature/*` / `release/*` / `hotfix/*`；非緊急 bug fix 歸 `feature/*`
   - **branch name 主體必須是純描述，不帶 issue number**——issue 已由目錄 `<issue-slug>` 與 PR `Closes #N` 表達，重複放進 branch name 是冗餘且會帶往後續所有 commit
     - ✅ `feature/fix-duplicate-nm-profiles`
     - ✅ `feature/notification-server-validation`
     - ❌ `feature/bug-42-fix-duplicate-nm-profiles`
     - ❌ `feature/issue-42-notification-validation`
3. 決定目錄名與 base——**先查這個 issue folder 底下已經有哪些 worktree**：

   ```bash
   ~/.claude/skills/x-worktree/scripts/worktree-inventory.sh \
     --issue-slug <issue-slug> --workspace <ardge-workspace>
   ```

   它掃過 workspace 底下每一個 main clone，跨 repo 的 issue folder 一次就列全。這件事手動做會漏：`git worktree list` 是按 main clone 回答的，只在手邊那個 repo 跑會看不到別的 repo 在同一個 issue folder 底下的目錄。

   先讀 `VERDICT:` 那行判斷這次量測算不算數（`ok` / `error` / `unavailable`），再讀 `WORKTREE:` 各列。一列 `WORKTREE:` 都沒有時，`ISSUE_FOLDER:` 那行的 `(exists)` 與 `(missing on disk)` 分辨得出「這個 issue 還沒開過任何 worktree」與「slug 打錯了」。

   **`(missing on disk)` 是新 issue folder 的訊號，也是前綴的唯一檢查點**：那一行印出來的 slug 與 step 0 判定的來源類型並排看一次，`bug-` / `spec-` / `issue-` / `review-pr-` 對不對得上。過了 step 4（代改流程是它的 step 2）目錄就建起來了，而既有目錄不改名（見〈目錄結構〉最後一條），所以錯的前綴在這之後沒有第二次機會。

   - **沒有 `WORKTREE:` 屬於這個 repo** → 目錄名 `<repo-name>`，base 是 `develop`
   - **有命中** → 這是同一份 spec 的第二刀，開新目錄 `<repo-name>_<task>`，**不要在既有目錄裡切 branch**。第二刀有兩種形狀，決定 base 的就是哪一種：

     | 形狀 | base | 什麼時候是這種 |
     | --- | --- | --- |
     | 並行獨立 | `develop` | 一份 spec 刻意切成互不相干的兩刀（例如同一支 API 的 GET 與 POST 各一刀），兩個 PR 同時進行，誰先 merge 都行 |
     | 疊加 | 上游那刀的 branch | 這一刀要讀上游的程式碼，而上游的 PR 還沒 merge。後續義務見〈疊在未 merged branch 上的那一刀〉 |

     兩種形狀都要兩個 checkout 同時存在，而一個 worktree 目錄只掛得住一個。在既有目錄裡切 branch 會抽掉 devcontainer 的掛載點；走到 `reset --hard origin/develop` 重起爐灶時，還沒 merge 的 commit 就只剩 reflog 撐著
4. 建立 worktree：`git -C <ardge-workspace>/<repo-name> worktree add <ardge-workspace>/worktree/<issue-slug>/<dir-name> -b <branch-name> <base>`（`<dir-name>` 與 `<base>` 來自步驟 3）
   - **Branch 衝突**：若 main repo 已在 develop 上（`git worktree add` 報 `'develop' is already used by worktree`），改用 detached HEAD：`git -C <ardge-workspace>/<repo-name> worktree add --detach <ardge-workspace>/worktree/<issue-slug>/<dir-name> origin/develop`。常見於不需要 feature branch 的場景（如直接用 develop 編譯部署）
5. **build 失敗在 submodule 路徑時，在 host 補齊**：`git -C <worktree 路徑> submodule update --init --recursive`

   `git worktree add` 只建出 submodule 的**空目錄**，不填內容。空目錄不會讓 git 報錯，壞的是讀那些檔案的 build，而訊息指向的是 build 步驟、不是 checkout——所以第一反應會是換一個 build 指令，不是回頭補內容。觸發判準是**錯誤訊息裡的路徑落在某個 submodule 目錄底下**（`git submodule status` 列得出來），不必先察覺什麼：

   - manager：`make build` 死在 `build-web`，`src/web` 是空的；改跑 `go build ./...` 會過，因為 Go 那半不讀它
   - api：`go build ./...` 自己就死在 `internal/wizardcontent/embed.go` 的 `go:embed`，`arx-welcome-wizard` 是空的；換指令沒有用，只能補

   **不預設做，兩個代價都是實測的**：worktree 的 submodule 有自己的 gitdir（`.git/worktrees/<name>/modules/…`），不共用 main clone 的 `.git/modules`，所以這是一次真的 clone、會走網路；補過之後 `git worktree remove` 會永久回 `fatal: working trees containing submodules cannot be moved or removed`（exit 128），連 `submodule deinit -f --all` 都解不掉，只剩 `--force`（見〈清理流程〉step 5）。

   **只能在 host 跑**：worktree **頂層**的 `.git` 是一個寫著 `gitdir:` 的檔案（與上一段那個 submodule 自己的 gitdir 是兩個東西），指向容器沒有 mount 的路徑，所以容器內需要 repo 的 git 指令一律失敗，submodule 這幾道也不例外。量測見 `x-environments/references/devcontainer.md`〈Worktree 的 container 內不能跑 git〉。

   跑完的對照：`ls -A <worktree 路徑>/<submodule 路徑>` 要有輸出。
6. 新建的 branch 不應設定 upstream（push 時才用 `git push -u origin <branch>` 建立）
7. 同一 issue 涉及多個 repo 時，對每個 repo 重複上述步驟，放在同一 issue folder 下

## 疊在未 merged branch 上的那一刀

這一節接在建立流程步驟 3 判定為「疊加」之後。名詞對應：**上游 branch** 是步驟 3 表格裡當 `<base>` 的那條；**下游**指這次新建的這一刀，它的 branch 是步驟 2 決定的 `<branch-name>`，路徑是步驟 4 建出來的 `<ardge-workspace>/worktree/<issue-slug>/<dir-name>`（以下寫成 `<下游路徑>`）。

步驟 4 的指令照原樣就能用，`<base>` 填上游 branch。上游已經在別的 worktree checkout 出來，但這不衝突：git 擋的是「同一條 branch 被兩個 worktree checkout」，而這裡即將 checkout 的是全新的 `<branch-name>`，上游只是被當成分出去的起點。

建立當下把**上游的 branch 名與當時的 tip SHA 寫進 issue folder 的 `PLAN.md`**。這不是留紀錄——上游之後幾乎一定會動（review 修正、rebase），而把下游接到新的上游需要知道舊的 tip 是哪一個：

- 上游只是**追加 commit** → `git -C <下游路徑> rebase <上游 branch>`
- 上游被 **rebase 或 force-push 過** → `git -C <下游路徑> rebase --onto <上游 branch> <PLAN.md 記的舊 tip> <branch-name>`。少了舊 tip 這個參數，直接 rebase 會把上游的舊 commit 連同新版一起帶進下游，變成成對的重複 commit

PR 的 base：下游開 PR 時 base 選上游的 branch，不是 develop——否則 diff 會把上游的改動算成下游的。上游 merge 之後回頭確認下游：`gh pr view <n> --json baseRefName`，還不是 develop 就 `gh pr edit <n> --base develop`。

## 代改別人 PR 的 branch

review 別人的 PR 時直接在他的 branch 上補 commit（例如文件修正）。取代建立流程的 step 1、2、4、6：

1. 先確認 head 在 origin 上：`gh pr view <n> --repo <owner>/<repo> --json isCrossRepository,headRefName`。`isCrossRepository` 為 `true` 表示 head 在 fork 上，本流程不涵蓋——不開 worktree，改在 review comment 裡提建議
2. 不開新 branch，以作者那條的遠端 tip 建一條追蹤它的本機 branch（`<dir-name>` 來自建立流程 step 3）：

   ```bash
   git -C <ardge-workspace>/<repo-name> fetch origin <headRefName>
   git -C <ardge-workspace>/<repo-name> worktree add --track -b <headRefName> <ardge-workspace>/worktree/<issue-slug>/<dir-name> origin/<headRefName>
   ```

   不用 `worktree add <path> <headRefName>` 的簡寫：本機若留著一條舊的同名 branch（例如之前 review 過同一個 PR），簡寫會直接 checkout 那條舊的、exit 0 不報錯，之後的 commit 就疊在過期的 tip 上。`-b` 的寫法遇到同名 branch 會以 `fatal: a branch named '…' already exists` 失敗——看到它就停下來回報，不自行 `branch -D` 或 `-f`，那條本機 branch 上可能有沒推的東西。

   追蹤關係是 step 6「不設 upstream」的例外：commit 要推回作者那條，追蹤正是要的

   commit 之前：改動碰到 API struct 註解、handler 或 `.proto` 時，在該 repo 跑對應的產生器（`make docs` / `make proto`），把生成檔一起 commit；Makefile 沒有該 target 就略過
3. push 用 `git push origin <headRefName>`，不 force-push。被拒（`fetch first` 或 `non-fast-forward`：作者在我 fetch 之後又推過）時**先問使用者**；預設做法是 `git -C <worktree> pull --rebase origin <headRefName>` 再重推——它只把我自己還沒推的 commit 重排到作者的新 tip 上，作者的歷史不動。force-push 會蓋掉作者的 commit，除了下一段的例外都不做

   唯一的例外是**使用者明確要求 rebase 這條 branch**(例如合併前要對齊 develop)。rebase 之前先記下要被取代的遠端 tip:`git -C <worktree> fetch origin <headRefName> && git -C <worktree> rev-parse origin/<headRefName>`,把印出的 SHA 留在回報裡——沒推過時它就是 step 2 的 tip,推過修正時它是自己最後一次 push 的 commit。push 寫成 `git push --force-with-lease=<headRefName>:<該 SHA> origin <headRefName>`:把 lease 釘在明確的 SHA，作者在那之後推過的話這次 push 會被拒，而不是蓋掉作者的新 commit。不帶 `:<SHA>` 時比的是本機的 `origin/<headRefName>`，中途任何一次 fetch 都會讓它失去保護(`git help push`,`--force-with-lease` 段落)。

   被拒時停下來問使用者，不要重新 fetch 後把 lease 改釘到新 tip 再推——那正是 lease 要擋的動作，作者剛推的 commit 會被蓋掉。使用者同意繼續時，丟掉本機這份 rebase 結果，以 `origin/<headRefName>` 為起點重新 rebase 到 develop、重新驗證，再以這次記下的 SHA 當 lease;把已 rebase 的結果直接疊到作者新 tip 上會產生成對的重複 commit。

   push 之後那則 comment 的內容:推了哪些 commit、各自改了什麼;有 rebase 的話附 PR 討論串(review comment、作者回覆)裡出現過的舊 SHA 與新 SHA 的對照，rebase 之後那些號碼全部失效。

清理照〈清理流程〉走；step 7 會因為 PR 作者不是自己而保留遠端 branch，不需要另外記得跳過。

## 路徑驗證

- **Every subagent must verify its cwd is the worktree path** (not the main repo) before any git or file operation. Use `pwd` or `git rev-parse --show-toplevel` to confirm
- 若工作目錄或 additional directory 含 `worktree/`，先用 `ls` 確認子目錄結構再操作，不憑印象推斷路徑

## 實作前置

- 建立 worktree 後，若先前探索階段的 Read 來自不同路徑（如原始 repo 目錄），必須在 worktree 目錄下重新 Read 要修改的檔案，才能執行 Edit
- 進入 worktree 操作某個 repo 時，先讀該 repo 的 `CLAUDE.md`（若存在），確保遵守專案規範
- 使用者通常在 `worktree/<issue-slug>/` 層級 prompt，但專案在下一層 `<repo-name>/`；確定操作目標專案後，先用 `ls` 確認子目錄結構，不憑印象推斷專案路徑

## 清理流程

**前置**：若 session 啟動 cwd 位於要刪除的目錄內，請使用者改由上層 session 執行 step 5、8。

1. **列出這個 issue folder 底下所有已註冊的 worktree，作為後面每一步的來源**：

   ```bash
   ~/.claude/skills/x-worktree/scripts/worktree-inventory.sh \
     --issue-slug <issue-slug> --workspace <ardge-workspace>
   ```

   `VERDICT:` 不是 `ok` 就停下來：`unavailable` 代表有 repo 讀不到、這份清單不完整，照著它刪會漏掉東西。**不要改用 `ls` 列 issue folder**：那裡除了 worktree 還有 `PLAN.md`、筆記、實驗用的暫存目錄，拿 `ls` 當來源會把它們當成 repo 目錄送進 `git worktree remove`。

   每一列的 `branch=` 要在這裡抄下來——`git worktree remove` 之後就問不出某個路徑原本掛哪條 branch，step 6 會沒有東西可讀。detached HEAD 的目錄印的是 `branch=(detached HEAD — nothing to delete)`，那一列 step 6、7 跳過，step 2 走 detached 那一支。

2. 確認刪掉本機這份不會丟東西——任何一項不成立就停下來回報，不往下走。以下 git 指令都在該 repo 的 main clone 跑（`git -C <ardge-workspace>/<repo-name> …`），`gh` 指令非零一律視同查不到、停下來：
   - **有 branch 的**，每一條先問遠端還在不在：`git ls-remote --exit-code --heads origin refs/heads/<branch>`。寫完整 ref 是因為 `--heads origin <branch>` 比對的是字尾，`foo/<branch>` 也會命中
     - exit 0（遠端還在）→ `git fetch origin <branch>`（非零就停：接下來比的會是過期的 `origin/<branch>`），再確認 `git merge-base --is-ancestor <branch> origin/<branch>` 是 exit 0，即本機沒有未 push 的 commit。用祖先關係不用相等：代改別人 PR 時作者常在我之後又推過，本機落後遠端不會丟東西
     - exit 2（遠端已不在，通常是 PR merge 時自動刪掉）→ 用 `gh pr list --repo <owner>/<repo> --head <branch> --state merged --json number` 取得 merged PR 的編號，`git fetch origin refs/pull/<number>/head`，再確認 `git merge-base --is-ancestor <branch> FETCH_HEAD` 是 exit 0。`refs/pull/<n>/head` 在 branch 被刪之後仍然保留，指向 PR merge 時的 head。
       - 不比對 commits 在不在 `origin/develop`：squash / rebase merge 之後那些 commit 不會出現在 develop 上
       - 不比對 head 是否等於本機 tip：代改別人 PR 時，作者常在我推完之後再補 commit 才 merge，那時 head 比本機新，但本機沒有東西會丟
     - 其他 exit code → 查詢失敗（斷網、認證），不能當成「遠端已刪」
   - **detached HEAD 的**：`git -C <path> log --oneline origin/develop..HEAD` 要是空的。step 3 的 `git status` 只看未 commit 的變更，detached 上已 commit 沒推的東西在 step 5 會直接丟掉
3. `git status` 確認無未提交變更
4. **對 step 1 列出的每一個路徑**，若其 devcontainer 仍在執行，先 stop（N 個目錄就跑 N 次；`<worktree-path>` 就是 step 1 印出的那個絕對路徑，label 比對的是絕對路徑）：

   ```bash
   CONTAINER_ID=$(docker ps --filter "label=devcontainer.local_folder=<worktree-path>" --format "{{.ID}}")
   [ -n "$CONTAINER_ID" ] && docker rm -f "$CONTAINER_ID"
   ```

   docker mount 持續佔住 worktree path 會讓後續 `git worktree remove` 卡 untracked artifacts，且容器孤兒佔用 docker 資源。

5. 對 step 1 列出的**每一個路徑**執行 `git worktree remove <path>`
   - 若因 untracked build artifacts 失敗，**必須暫停並明確取得使用者同意**後才加 `--force`，禁止在描述中自行判定後直接執行
   - `fatal: working trees containing submodules cannot be moved or removed`（exit 128）是**另一個原因、同一個症狀**：這個 worktree 補過 submodule（建立流程 step 5）。`submodule deinit -f --all` 解不掉，實測 deinit 之後照樣 128，所以這裡唯一的出路就是 `--force`。它與上一列的差別在於沒有東西會遺失——submodule 的內容重跑一次 init 就回得來——但**照樣要先問**，因為問的理由是「`--force` 這個動作要使用者同意」，不是「這次風險高不高」
6. 對 step 1 抄下的**每一條 branch** 執行 `git -C <ardge-workspace>/<repo-name> branch -d <branch>`。還沒 merge 進 HEAD 的 branch 會印 `not yet merged to HEAD` 的 warning 但照樣刪除——前提是這條 branch 設了 upstream、而那個 upstream ref 還在，它已 merge 進那裡。沒設 upstream，或 ref 被 prune 掉之後（常見於遠端 merge 時自動刪除、又跑過 `fetch --prune`），`-d` 改拿 main clone 的 HEAD 比，squash merge 的 branch 會回 `not fully merged` 拒絕。遇到就停下來，附上 step 2 的證據請使用者同意，不自行改用 `-D`
7. **刪遠端 branch 要有正面證據**，每一條各查一次，兩個指令都要 exit 0：

   ```bash
   gh api user --jq .login
   gh pr list --repo <owner>/<repo> --head <branch> --state all --json author,state
   ```

   以下全部成立才刪（先 `git ls-remote --exit-code --heads origin refs/heads/<branch>` 確認遠端還在——exit 2 表示已經不在，不用刪；其他非零是查詢失敗，跳過——exit 0 才 `git push origin --delete <branch>`）：
   - 至少查到一筆 PR，且**每一筆**的 `author.login` 都是我——`--head` 只比對 branch 名稱，fork 上同名 branch 的 PR 也會被查到
   - 至少一筆 `state` 是 `MERGED`
   - 沒有任何一筆是 `OPEN`——刪掉 open PR 的 head，GitHub 會把那個 PR 關掉

   其他情況一律跳過，並在回報寫明「遠端 branch 保留，原因 X」（PR 作者不是我／PR 還開著／PR 已關閉未 merge／查不到 PR／`gh` 查詢失敗）。不刪的預設是刻意的：多留一條 branch 隨時能手動刪，刪錯的要有人發現、再到 PR 頁面按 Restore branch 才救得回來。CLOSED 未 merge 也保留，因為它可能是放棄，也可能只是擱著，光看狀態分不出來
8. 清掉 issue folder 殼層——**只能用 `rmdir`，不可 `rm -rf`**：
   - `rmdir <issue-folder>` 成功 → 完成
   - 失敗（`Directory not empty`）→ `ls -la <issue-folder>` 列出剩餘內容回報給使用者，由使用者決定保留哪些、刪哪些。常見保留物：跨 repo 的 `PLAN.md`、筆記、design doc。**禁止自行 `rm -rf` 通過障礙**
   - 用 `rmdir` 的理由：跑完 step 5 後 issue folder 理應只剩空殼，非空就是訊號（有刻意保留的 artifact，或 step 5 漏跑、有 untracked 殘留），需要看過再決定，不該無聲掩蓋

## Worktree session 中重 build 失敗 recovery

`make docker-image` / `docker buildx bake` 在 worktree devcontainer 內偶發失敗於 `buildkit metadata_v2.db: input/output error`，伴隨 container 從 `docker ps` 消失。原因是 dind buildkit state 損壞。

Recovery：

1. 確認 container 真的消失：`docker ps --filter "label=devcontainer.local_folder=<project-dir>"`
2. 重啟：`devcontainer up --workspace-folder <project-dir> --remove-existing-container`
3. 重新前置檢查（docker ps），再重跑 build

不要嘗試在 host 端清 `/var/lib/buildkit`（那是 dind 內部，host 看不到）。直接讓 devcontainer up 重建 dind state 最乾淨。
