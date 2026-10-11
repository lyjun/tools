# DevContainer 環境

## 強制原則

對任何專案目錄執行 build/test/lint 前，若該目錄含 `.devcontainer/`，**必須**先執行以下檢查：

```bash
docker ps --filter "label=devcontainer.local_folder=<project-dir>" --format "{{.Status}}" 2>/dev/null
```

> **注意**：`<project-dir>` 是實際要操作的專案目錄的**絕對路徑**，不是 `$(pwd)`。在 worktree 場景下 `$(pwd)` 可能是 worktree 根目錄，與專案目錄不同。

- `docker ps` **exit code 非零** → Docker 未執行，直接使用本機環境
- `docker ps` **成功但無匹配 container** → 嘗試建立並啟動：`devcontainer up --workspace-folder <project-dir> --remove-existing-container`
  - **exit 0** → 成功，使用 `devcontainer exec` 執行指令
  - **exit 非零但訊息含 `postCreateCommand failed`** → container 可能已啟動但 post-setup 失敗（worktree 場景常見：git path 在容器內不可達，機制與後續影響見下方「Worktree 的 container 內不能跑 git」）。重新執行 `docker ps --filter ...` 檢查，若 container 顯示 `Up` 則可正常使用 `devcontainer exec`
  - **exit 非零且無 container 啟動** → 回報錯誤，改用本機環境
- container **運行中** → 後續所有 build/test/lint 指令必須透過 `devcontainer exec --workspace-folder <project-dir> <cmd>` 執行，不需使用者提醒

**不得在任何情況下跳過此檢查。** 使用者不應需要手動糾正「忘記用 devcontainer」。

**在 host 上跑 `make fmt` 時（含退回本機環境，以及 host `git commit` 觸發的 lefthook pre-commit `fmt`），它會改動 repo 自己的 toolchain 與 CI 認為已格式化的檔。** host 的 Go 可能比 repo 釘的新，而 gofmt 對某些寫法的縮排在版本之間改過（例：host Go 1.27 對 `arx-platform-core` 的 go 1.26.6，`make fmt` 改了這條 branch 從沒碰過的 `internal/services/storage/backup_target.go`）。它讀起來像別人 branch 上的格式漂移，commit 進去會把一段無關的重排塞進 review。所以 `make fmt` 之後不要從 `git status` 整批 stage：只 stage 自己編輯過的路徑，再看一次 `git status`，仍是 modified 的就是重排，用 `git checkout --` 還原。要確認是版本差而不是真的漂移，看 `git diff --stat origin/develop...HEAD -- <path>`：空的代表這條 branch 沒碰過那個檔。

## Worktree 多專案場景

Worktree 目錄下包含多個獨立專案時：

1. **確定操作目標專案後，第一步**：確認 `<project-dir>/.devcontainer/` 是否存在
2. **存在** → 立即執行上方的 `docker ps --filter ...` 前置檢查
3. **前置檢查完成前** → 禁止執行任何 build/test/lint 指令

每個專案有各自的 `.devcontainer/` 設定和獨立的 container。`--workspace-folder` 必須指向該專案的絕對路徑，不得用 worktree 根目錄。

### 多專案都要驗時，開機與容器內的工作分開排程

一個 issue 橫跨多個 repo、而且 repo 之間有「上游先推、下游才能重新產生」的相依時，容易把整串排成一條：開上游的容器 → 做完 → 推 → 開下游的容器 → 做完。**這條把開機也串進去了，而開機不需要串。**

判準是機械的，看那道指令**有沒有讀到別的 repo 剛推上去的東西**：

| 指令 | 讀上游嗎 | 要不要等 |
|---|---|---|
| `devcontainer up` | 否，只準備容器 | 不用等，可以先全部發動 |
| `buf generate` / `make proto` / 任何拉遠端契約的 target | 是 | 這一步才 gate 在上游 push 之後 |

第一列有機械的對照點，不必憑印象：`grep -nE 'onCreateCommand|postCreateCommand|updateContentCommand' <repo>/.devcontainer/devcontainer.json`，再讀它指到的腳本。哪天有 repo 把 `make proto` 放進 `postCreateCommand`，那個 repo 的 `devcontainer up` 就自己換到第二列去了。（2026-09-11 查過 manager / core / api，三份 `setup.sh` / `post-setup.sh` 只做 `mise install`、docker login、`lefthook install`——`mise install` 會走網路但不讀別的 repo，所以第一列照這個判準仍然成立。）

所以用 `run_in_background` 把下游各 repo 的 `devcontainer up` 先發動，等上游 push 完成之後才逐個 `devcontainer exec` 進去跑那道會讀上游的指令。

**背景發動不豁免〈強制原則〉。** 發動前每個 repo 各跑一次 `docker ps --filter`（已經有 container 就不必 up），而 `devcontainer exec` 之前要回頭再查一次 `docker ps`：背景那趟的 exit code 要等它結束才拿得到，而 `postCreateCommand failed` 正是 exit 非零但 container 已經 `Up` 的那一種，只有重查分辨得出來。

實測的反例（2026-09-10，proto → manager / core / api 的契約重生）：四次 `devcontainer up` 落在 10:04:25、10:05:50、10:09:45、10:13:30，完全串行；而真正依賴 proto 的只有容器裡的 `make proto` 那一行（manager 那次在 10:06:55 才跑，確認抓到新的 branch tip）。三個下游容器的開機彼此無關，也與 proto 的 push 無關，卻各自等了前一個做完才開始。

**未驗：這台機器同時扛得住幾個 dind 容器。** 四個一起發動沒測過，保守分兩批；真要一次全開，先確認記憶體，別把驗證的時間省在讓機器換頁上。

### Worktree 的 container 內不能跑 git

worktree 的 `.git` 不是目錄，是一個內容為 `gitdir: <主 clone 路徑>` 的檔案（實測 96 bytes），指向的路徑在 mount 之外，所以**容器內任何需要 gitdir 的 git 指令都會失敗**——`checkout`、`rev-parse`、`stash` 都算，不只是 submodule 的操作。**「只有 submodule 會壞」是錯的**，這點量過三次：`arx-platform-core` 一個完全沒有 submodule 的 worktree（`git submodule status` 空輸出）只把自己掛進容器，`rev-parse HEAD`、`status`、`stash list`、`checkout -- go.mod` 四個都回同一句 fatal、exit 128（2026-09-11）；worktree 的 devcontainer build 裡 Makefile 的 `git rev-parse --short HEAD` 失敗，`GIT_COMMIT` 因此內嵌成 `unknown`（2026-09-08，見記憶 `reference_worktree_devcontainer_gitcommit_unknown`）；以及下面那次 `RESTORE_EXIT=1`。失敗訊息是 host 端的絕對路徑，讀起來像路徑打錯：

```
fatal: not a git repository: /Users/x/Workspace/ardge/arx-os-installer/.git/worktrees/arx-os-installer2
```

因此需要刻意改壞一個受版控的檔案時（例如要確認新加的守衛測試真的會擋，而不是只在乾淨的樹上通過），**改壞與改回都在 host 用 git 做，不要在容器內還原**。實測代價：容器內 `git checkout <file>` 還原失敗（`RESTORE_EXIT=1`），改壞的檔案留在工作區，只因為那次指令最後一步印了 exit code 才被發現。同一根因也會讓 `make` 目標裡的 `git rev-parse` 掛掉，見 arx-os-installer 的 `manifest-keys`。

## 範例

- `make build` → `devcontainer exec --workspace-folder <project-dir> make build`
- `go test ./...` → `devcontainer exec --workspace-folder <project-dir> go test ./...`

## Docker-in-Docker (dind)

DevContainer 使用 dind，內部有獨立的 Docker daemon。dind 的檔案系統與 host 及 devcontainer workspace 隔離——`docker save -o`、`docker cp` 等指令產生的檔案在 dind 內部，需透過管線或 workspace mount 路徑傳出才能從 host 存取。

### 檔案從 DevContainer 傳出

Container 內的 `/tmp` 等非 workspace 路徑無法透過 `docker cp <container>:/tmp/...` 存取（dind 隔離）。需先將檔案 cp 至 workspace mount 路徑：

```bash
# container 內 build 產物在 /tmp/binary
devcontainer exec --workspace-folder <project-dir> cp /tmp/binary /workspaces/<repo>/binary
# host 端從 worktree 路徑存取
ls <project-dir>/binary
```

用完後清理 workspace 內的暫存檔，避免意外 commit。

## Buildx Builder 分層

Host 和 devcontainer 內各有獨立的 Docker daemon，buildx builder 設定互不影響：

| 環境 | 預設 Builder | Driver | 說明 |
|------|-------------|--------|------|
| **Host** | `desktop-linux` | docker | Docker Desktop daemon，網路直通 host |
| **DevContainer (dind)** | `dev-builder` | docker-container | 獨立 daemon，支援 multi-platform build |

**禁止在 host 上建立 `docker-container` driver 的 builder**——該 driver 的網路與 host 隔離，build 時會網路不通。`dev-builder` 只應存在於 devcontainer 的 dind 內。
