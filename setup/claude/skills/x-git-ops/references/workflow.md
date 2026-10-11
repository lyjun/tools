# Workflow Reference

Detailed procedures for non-commit git operations. The branch-protection,
commit-rules, and `git -C` guards in `SKILL.md` apply throughout.

## Branch Naming & Base

Prefix 只能是 `feature/*`、`release/*`、`hotfix/*`（Git Flow）。非緊急 bug fix 歸類為 `feature/*`。

- `feature/*` **必須**從 `develop` 分出 — 從 `main` 分會缺少 develop 上其他人已合併的變更
- `hotfix/*` **必須**從 `main` 分出 — hotfix 修的是 production 程式碼，必須基於 production
- 建立 branch 時明確指定 base，避免從當前 HEAD 推測：`git fetch && git switch -c feature/x origin/develop`（或 `hotfix/y origin/main`）。**注意這個寫法會把 upstream 設成 `origin/develop`**（start-point 是 remote-tracking ref 就會 tracking），除非你要的就是這個，否則接著 `git branch --unset-upstream`；後果與解除方式見「跨長期分支 cherry-pick」
- 事後驗證 base 對不對：`git log --oneline origin/<expected-base>..HEAD` 應只列出此 branch 的工作 commits；若混入大量「應在 base 上」的 commits，表示分錯了

## Commit Splitting

- CLI doesn't support `git add -p` — merge commits sharing same file (default) or use patch files
- Order: types/interface → implementation → wiring. Generated code (proto) gets its own commit
- Target 3-5 commits. Verify: `git diff <original>..HEAD` should be empty
- **Cherry-pick 前先整理**: 若 commit 混合多個 concern，先在原 branch 上按 concern 重整為獨立 commit（`reset --soft` + 分次 staging），再 cherry-pick 到各 branch。避免跨 concern commit 造成 conflict

## Push

Before `git push`, check upstream with `git rev-parse --abbrev-ref @{upstream}`.
If no upstream is set, use `git push -u origin <branch>` to establish tracking.

裸 `git push` 的目標由 `push.default` 決定（`git config push.default`，未設時為 `simple`）。`simple` 在 upstream 與當前分支同名時才推送，名稱不符會拒絕；`upstream` 則推往 upstream 指向的分支，與當前分支名無關。upstream 指向保護分支時這個差別決定了會不會直接推上去，見「跨長期分支 cherry-pick」。

## Branch Operations

Confirm target branch in main conversation before using an Agent subagent for checkout/rebase.

## Cherry-pick

If commits mix multiple concerns, squash by concern first (see Commit Splitting). Then evaluate conflicts: `git diff <base>..<target> -- <files>`. Warn user about expected conflicts before executing.

### 跨長期分支 cherry-pick

在兩條長期分支之間搬 commit 時（`develop` → `release/*`、`release/*` 或 `main` → `develop`、release 線之間，方向不拘），base 不是平常的 `develop`，以下四點與一般 cherry-pick 不同：

- **從 remote-tracking ref 開 branch 會自動設 upstream 到那條保護分支**（`branch.autoSetupMerge` 預設 `true`）。建立後立刻 `git branch --unset-upstream`，並用 `git rev-parse --abbrev-ref '@{u}'` 確認已解除。以本地 branch 名當 start-point 則不會發生。不解除的三種後果，實測：裸 `git pull` 會**靜默地**把保護分支 merge 進你的工作 branch；`git status -sb` 與所有讀 `@{upstream}` 的工具都對錯的 base 報 ahead/behind；裸 `git push` 在預設的 `push.default=simple` 下會以「upstream branch 名稱不符」明確拒絕，但若 `push.default=upstream` 就會直接推上保護分支
- **依賴釘版的 commit 要個別判斷，不能整段照抄**。來源 PR 常夾帶 `build(deps): pin <dep> to vX`，而兩條分支的 pin 各自演進，可能較新也可能較舊。先讀目標分支的 pin 檔（`buf.gen.yaml`、`go.mod`、submodule pointer）比對版本再決定取捨——目標較新就跳過（否則降版並砍掉中間版本的生成綁定），目標較舊才需要一併帶過去。別無腦 `<merge>^1..<merge>`
- **保真關卡分兩步，第二步才是判準**。`git range-diff <來源範圍> <base>..HEAD` 用來看差異落在哪裡，但它的 `!` 不能當失敗訊號——按 concern 重整或 squash（見 Commit Splitting 與本節開頭）會改變 commit 邊界，刻意跳過釘版 commit 會缺項，兩者都是照規則做對的結果。判準是接著跑 `git diff <來源 merge> <base>..HEAD -- <手寫檔清單>`：輸出必須為空，例外只有你明確決定不帶過去的檔案。這是對得上具體物件的 yes/no 檢查，不需要先察覺什麼。生成檔不納入這份清單——兩邊 pin 不同時本來就會有差異，取手寫檔後在目標分支重跑產生器（`make proto` / `make docs`），不要手動合 hunk
- **merge 後必須驗落地**：`git branch -r --contains <merge sha>` 要真的印出目標分支。PR 顯示 MERGED 不代表程式碼在活分支上——若它 merge 進的 ref 事後被刪除或重設，merge commit 會變成任何分支都到不了的孤兒

## Rebase/Amend Safety (mandatory)

**Before**: `T=backup-$(date +%Y%m%d-%H%M%S); git tag "$T" HEAD && echo "created $T"` — 印出的名字要留在回報或 PLAN.md 裡,After 那步 `tag -d` 的參數從這裡抄;跨多個 repo 時每個 repo 的名字各記一行
**After**: `git diff backup-<tag>..HEAD --stat` — warn on unexpected changes, then `git tag -d backup-<tag>`

刪 tag 時寫出 Before 那步實際建出來的完整名字，不用 pattern(`backup-*`、`tag --list | xargs`)。`backup-` 是每一輪 rebase 共用的前綴，同一個 clone 裡常留著別的工作的 backup——用 pattern 清一次就把它們一起刪了，而 `tag -d` 之後只剩它當下印出的 SHA 能把它們補回來。

**Traps**: Verify `git diff --cached --stat` before amend. Confirm both commits' files survive squash/fixup.
