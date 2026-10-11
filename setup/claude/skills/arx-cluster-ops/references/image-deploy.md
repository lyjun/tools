# k8s Workload Deploy

部署 locally-built container image 到 ARX k3s cluster 的 k8s workload（Deployment、DaemonSet 等）。

## Prerequisites

- SSH access to the target machine
- Image built locally (via devcontainer `make docker-image` or equivalent)
- Target machine runs k3s

## Critical: k3s Containerd

k3s 有自己的 containerd，跟系統的 containerd 完全獨立。

| Command | Wrong | Correct |
|---------|-------|---------|
| Import image | `ctr -n k8s.io images import -` | `k3s ctr -n k8s.io images import -` |
| Tag image | `ctr -n k8s.io images tag` | `k3s ctr -n k8s.io images tag --force` |
| List images | `ctr -n k8s.io images ls` | `k3s ctr -n k8s.io images ls` |

用系統 `ctr` import 的 image 會出現在 `ctr images ls` 但 kubelet 永遠找不到。

## Step 1: Export Image

From devcontainer (dind) — image 在 dind daemon 裡，不在 host：

```bash
devcontainer exec --workspace-folder <project-dir> \
  bash -c 'docker save <image>:<tag> | gzip > /workspaces/<repo>/<name>.tar.gz'
```

Tarball 出現在 host 的 `<project-dir>/<name>.tar.gz`（workspace mount）。

## Step 2: Transfer to Remote

遠端檔名每次不同，避免 `/tmp` 裡留著 root 擁有的同名舊檔，導致 scp 失敗、後面讀到舊檔。
記下這個路徑（下稱 `<remote-tar>`），Step 4 與 Cleanup 都用它：

```bash
R=/tmp/<name>.$(date +%s).tar.gz; echo "$R"
SSHPASS='<pw>' sshpass -e scp -o StrictHostKeyChecking=no -o PubkeyAuthentication=no \
  <local-path>.tar.gz <user>@<host>:"$R"; echo "scp=$?"
```

## Step 3: Suspend Flux

防止 Flux reconcile 蓋回你的修改：

```bash
KUBECONFIG=/etc/rancher/k3s/k3s.yaml flux suspend helmrelease -n arx-system <release-name>
```

## Step 4: Import and Tag

```bash
gunzip -c <remote-tar> | k3s ctr -n k8s.io images import -

k3s ctr -n k8s.io images tag --force <build-image>:<build-tag> <original-repository>:<version>-dev
```

`<original-repository>` 是 workload 現在那個 image 去掉 tag 的部分（用 Step 6 的指令讀）。tag 一定要是
registry 上沒有的新名字（例如加 `-dev`）：沿用原 tag 時 `--force` 會把 containerd 裡的原 image 換成
測試版，Cleanup patch 回原 image 時跑的仍是測試版。

Common build image names:
- `ghcr.io/ardge-labs/<repo>:dev` (from `make docker-image` / bake `image-local`)

## Step 5: Patch and Restart

Patch 之前先記下原本的 image 與 imagePullPolicy（Step 6 的指令就能讀），那是唯一的還原依據——
Flux 不會幫你記，見 Cleanup。

```bash
kubectl patch <resource-type> -n arx-system <name> --type=json \
  -p '[
    {"op":"replace","path":"/spec/template/spec/containers/0/image","value":"<original-repository>:<version>-dev"},
    {"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}
  ]'

kubectl rollout restart -n arx-system <resource-type>/<name>
kubectl rollout status -n arx-system <resource-type>/<name> --timeout=120s
```

**imagePullPolicy 必須改 `IfNotPresent`** — locally-imported image 不在 registry，`Always` 會觸發 `ErrImagePull`。

## Step 6: Verify

```bash
kubectl get pods -n arx-system -o custom-columns=\
'NAME:.metadata.name,IMAGE:.spec.containers[0].image,PULL:.spec.containers[0].imagePullPolicy,STATUS:.status.phase' \
  | grep <service-name>
```

## Cleanup

**順序不可調換**——先把 workload 換回原 image 並確認 rollout 完成，才移除測試 image：

```bash
# 1. Patch 回 Step 5 記下的兩個原值（resource-type 與部署時相同）
kubectl patch <resource-type> -n arx-system <name> --type=json \
  -p '[
    {"op":"replace","path":"/spec/template/spec/containers/0/image","value":"<original-image>"},
    {"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"<original-pull-policy>"}
  ]'
kubectl rollout status -n arx-system <resource-type>/<name> --timeout=180s

# 2. 確認 pod 真的跑在原 image 上（Step 6 的指令）

# 3. Resume Flux
KUBECONFIG=/etc/rancher/k3s/k3s.yaml flux resume helmrelease -n arx-system <release-name>

# 4. 移除測試 image 與 tarball（只刪 Step 2 那個路徑，不用萬用字元——/tmp 裡可能有別人的檔）
k3s ctr -n k8s.io images rm <original-repository>:<version>-dev
rm <remote-tar>
```

### `flux resume` 不會還原 `kubectl patch`

`flux resume`、甚至 `flux reconcile --force`，都**不會**把 Step 5 patch 掉的 image 與 imagePullPolicy 拉回來。
Helm 存的 release manifest 本來就寫著原版 tag，upgrade 時該欄位沒有 diff，三方合併因此不會去
碰 live 物件；out-of-band patch 只能自己 patch 回去。

實際踩過的後果：以為 resume 就還原了，先移除測試 image，pod 卻還在用它——當下沒事（container
已建立），但只要 pod 重啟就 `ErrImagePull`，因為那個 tag 在 registry 上不存在。

## SSH Script Pattern

多步驟遠端操作用 SCP script 模式（避免 heredoc 引號問題）。遠端檔名每次不同（理由同 Step 2），
輸出寫進遠端 log，失敗時才有東西可查：

```bash
cat > /tmp/deploy.sh << 'EOF'
#!/bin/bash
k3s ctr -n k8s.io images import ...
EOF

S=/tmp/deploy.$(date +%s).sh
SSHPASS='<pw>' sshpass -e scp -o PubkeyAuthentication=no /tmp/deploy.sh <user>@<host>:$S; echo "scp=$?"
SSHPASS='<pw>' sshpass -e ssh -o PubkeyAuthentication=no <user>@<host> \
  "echo '<pw>' | sudo -S bash $S >$S.log 2>&1; echo exit=\$?; tail -20 $S.log"
```

`scp` 不是 0 就停。

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `ErrImagePull` after import | Used system `ctr` instead of `k3s ctr` | Re-import with `k3s ctr` |
| `ErrImagePull` with `IfNotPresent` | Image tag mismatch | `k3s ctr -n k8s.io images ls \| grep <name>` |
| `ErrImageNeverPull` | `imagePullPolicy: Never` but image not found | Verify tag matches pod spec |
| Pod reverts to old image | Flux reconciled | `flux suspend helmrelease -n arx-system <name>` |
| `ImagePullBackOff` persists after fix | kubelet caches pull failures | Delete pod, let controller recreate |
