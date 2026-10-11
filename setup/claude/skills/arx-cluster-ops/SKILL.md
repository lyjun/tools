---
name: arx-cluster-ops
description: "ARX k3s cluster operations — image deployment, service management, Flux GitOps handling, and cluster-side troubleshooting on ARX dev/test/production machines. Use this skill whenever the user is working on an ARX cluster: deploying or updating services, debugging failures, recovering stuck states, or performing any hands-on cluster operations. Also trigger when credentials for a remote ARX host are provided, or when ARX-related pod or service issues appear (failures, stuck upgrades, service not ready). Trigger on upgrade failures specifically: upgrade-state configmap shows state=failed, upgrade API returns any error, or progress is stuck — load upgrade-debug-flow.md. Also trigger when the user is about to initialize an ARX host, and when initialization is slow or stuck downloading from GitHub (k3s binary, ghcr.io images, GitHub release assets, raw.githubusercontent.com). If uncertain whether the target is an ARX cluster, ask the user or do a quick probe (`k3s --version` over SSH)."
model: sonnet
effort: medium
---

# ARX Cluster Operations

Operational knowledge for deploying and managing services on ARX k3s clusters.

## Quick Reference

| Item | Value |
|------|-------|
| Container runtime | k3s bundled containerd (`k3s ctr`, **not** system `ctr`) |
| Image namespace | `k8s.io` |
| Services namespace | `arx-system` |
| Registry prefix | `registry.<channel-domain>/ardge/<repo>:<version>` — unstable `registry.ardge.me`、testing `registry.ardge.xyz`、stable `registry.ardge.com`（來源 `arx-manifest-sources` 的 `shared/channel-sources.yaml`）。實際值以現場 workload 或 unit 裡的 image 為準 |
| GitOps | Flux HelmReleases |
| kubeconfig path | `/etc/rancher/k3s/k3s.yaml` |
| `arx-platform-core` workload | DaemonSet (not Deployment) — restart with `kubectl rollout restart daemonset arx-platform-core -n arx-system` |

## Upgrade Failure

兩條觸發路徑（任一即載入此區塊指向的 reference）：

- `upgrade-state` configmap 出現 `state: failed` / `error_code` 非空 / `progress` 卡住
- 升級相關 API call 回傳任何錯誤（不限特定錯誤碼）

→ 載入 [`references/upgrade-debug-flow.md`](references/upgrade-debug-flow.md)，依其中的 observe / collect / analyze 流程進行。

收集完所有相關層級的資料前，**不要**跳到修復步驟。

## Init 下載卡在 GitHub 網段

症狀：init 卡在下載 k3s 二進位檔或 ghcr 映像，一卡幾十分鐘。原因在網路不在 code：
GitHub 資產 CDN（185.199.108.0/22，Fastly）在辦公室出口逐條 TCP 抽籤，
多數連線只剩 60–85 KB/s。

**0. 使用者說要 init 一台主機時先提示一句**，不等它卡住：「如果 init 卡在下載 k3s 或 ghcr 映像，
可以先量 GitHub 吞吐量，確診後用 WARP 把 GitHub 網段改走 Cloudflare。」
未驗：改路由之後，已經卡住的那條連線會不會變快。所以在 init 前開比較可靠，卡住後才開就讓 init 重跑。

**1. 先在 ARX 主機上量（一分鐘）**，確認是這一型：

```bash
curl -sS -o /dev/null -L --max-time 12 -r 0-20971520 \
  -w 'remote=%{remote_ip} speed=%{speed_download} B/s\n' \
  'https://github.com/k3s-io/k3s/releases/download/v1.36.4%2Bk3s1/k3s-arm64'
curl -sS -o /dev/null --max-time 12 \
  -w 'speed=%{speed_download} B/s\n' 'https://speed.cloudflare.com/__down?bytes=52428800'
```

第一條只有幾十 KB/s、第二條是 MB/s 才算確診，否則不要往下做。
只量一次可能剛好抽到快的連線，第一條要多跑幾次。

**2. 開 WARP 前先問使用者**，因為它會在這台機器註冊一個 Cloudflare 裝置
（等於接受 Cloudflare 的服務條款），並改掉主機的路由。
只用不帶參數的模式（unit 寫在 `/run`）：萬一路由壞掉、SSH 斷線，主機斷電重開就會回到原狀，
這個還原不依賴主機本身還連得上。

**3. 把 script 複製到主機並執行**。檔名每次不同，避免 `/tmp` 裡留著 root 擁有的舊檔，
導致 scp 失敗、後面跑到舊版；輸出寫進主機上的 log，失敗時才有東西可查：

```bash
S=/tmp/warp-github-split.$(date +%s).sh
SSHPASS='<pw>' sshpass -e scp ~/.claude/skills/arx-cluster-ops/scripts/warp-github-split.sh <user>@<host>:$S; echo "scp=$?"
SSHPASS='<pw>' sshpass -e ssh <user>@<host> "echo <pw> | sudo -S bash $S >$S.log 2>&1; echo exit=\$?; tail -20 $S.log"
```

`scp` 不是 0 就停。script 每條結束路徑最後都印一行 `VERDICT:`，讀那一行：

| VERDICT | 意思 |
|---|---|
| `ok` | 185.199.108.0/22 走 `dev CloudflareWARP`，1.1.1.1 不走 WARP（上面兩行印著實際網卡） |
| `error` | 參數錯，或沒用 root 跑 |
| `unavailable` | 跑了但沒達成：路由不對、下載失敗、`wait_for` 30 秒逾時、排除清單算不出來（此時停在斷線狀態，不會連上 WARP）。看 log 裡 VERDICT 上面的訊息 |

之後隨時可以用 `bash $S status` 重查。設好後重跑第 1 步的第一條，記下速度。

**4. init 跑完就執行 `remove`**，指令同第 3 步，只把 `bash $S` 換成 `bash $S remove`。
中途重開過機的話 `$S` 已經不在（`/tmp` 在每次開機清空的 root overlay 上），要重新 scp。它會刪掉 `/var/lib` 底下的檔案和
Cloudflare 端的註冊；註冊刪不掉時檔案照刪，但回 `VERDICT: unavailable` 並說明註冊可能還留著。
這兩樣只靠重開機不會清掉。

沒涵蓋的部分：deb.debian.org（146.75.x）一樣慢，但不在範圍內；IPv6 整段排除在 WARP 外。

## SSH sudo 環境下的 kubeconfig

k3s 安裝時把 `kubectl` 設成 k3s 的 symlink，sudo 內**不需要** export KUBECONFIG。
但 `flux` 與 `helm` 是獨立 binary，找不到 `~/.kube/config` 會 fall back 到
`localhost:8080` 失敗（典型錯誤：`dial tcp [::1]:8080: connect: connection refused`）。

執行 `flux` / `helm` 前必須先 export：

```bash
echo <password> | sudo -S bash -c '
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
flux suspend helmrelease ... / helm upgrade ...
'
```

純 `kubectl` 指令不需要這個 export。混用時統一加上即可。

## Deploy: Which Flow?

ARX 有兩種服務類型，部署方式不同：

| 判斷方式 | 類型 | 參考文件 |
|---------|------|---------|
| `kubectl get deploy,ds -n arx-system` 有對應資源 | k8s workload | [image-deploy.md](references/image-deploy.md) |
| `systemctl cat <service>` 有對應 unit | Host service (systemd) | [host-service-deploy.md](references/host-service-deploy.md)——先依 unit 的寫法分流：解出 binary 的（manager、console）與直接 `nerdctl run` 的（hal、discover）做法不同 |

不確定時，兩邊都查一下。

## Build Tag Awareness

部署前確認 build tags — 某些 tag 會改變 runtime 行為：

| Tag | Effect |
|-----|--------|
| `dev` (in BUILD_TAGS) | Dev middleware（如 fake auth） |
| `mockdbus`, `mocknft` | 所有 dbus/nft 呼叫變 no-op（reboot、shutdown、firewall 不會執行） |
| `reflection`, `pprof` | 啟用 gRPC reflection 和 profiling endpoint，不影響業務邏輯 |
| 空 (release build) | Production 行為 |

確認方式：
- 編譯前：查 `docker-bake.hcl` 的 `BUILD_TAGS` arg
- 部署後：查 service startup log（`journalctl -u <service> | grep -i mock`）
