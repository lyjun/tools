# Host Service Deploy Procedure

Step-by-step procedure for deploying locally-built binaries to ARX host services (systemd-managed, not k8s pods).

## Prerequisites

- SSH access to the target machine (use `sshpass` with credentials from user)
- Images built locally (via devcontainer `make docker-image` or equivalent)
- Know the service name — check with `systemctl cat <service>` on the target machine

## Which Procedure: Read the Unit First

`systemctl cat <service>` 決定走哪一套，兩種 unit 的做法不同：

| Unit 長這樣 | 例子 | 走哪裡 |
|---|---|---|
| `ExecStartPre` 用 `nerdctl create` + `nerdctl cp` 把 binary 解到 host，`ExecStart` 跑那個 binary | arx-manager、arx-console | 下面 Step 1–5 |
| `ExecStart=nerdctl run … <image>`，程式在 container 裡跑，沒有解出 binary 這一步 | arx-hal、arx-discover | 〈Units That Run the Container Directly〉 |

後一種照 Step 1–5 做不會報錯：binary 被複製到 `/usr/local/bin` 但沒有人讀它，重啟後跑的仍是舊 image，
`systemctl is-active` 照樣是 active。

## How Host Services Normally Deploy

The extract-style services have `ExecStartPre` steps that extract the binary from a container image on every restart:

```
ExecStartPre=-nerdctl pull registry.<channel-domain>/ardge/<service>:<version>
ExecStartPre=nerdctl create --network=none --name <extractor-name> <image>
ExecStartPre=nerdctl cp <extractor-name>:/usr/local/bin/<binary> /usr/local/bin/<binary>
ExecStartPre=nerdctl rm <extractor-name>
```

Actual service/binary names vary — check the systemd unit file (`systemctl cat <service>`) for exact values.

## Step 1: Build and Export

Same as container deploy — build image in devcontainer, export tarball:

```bash
devcontainer exec --workspace-folder <project-dir> make docker-image
devcontainer exec --workspace-folder <project-dir> \
  bash -c 'docker save <image>:<tag> | gzip > /workspaces/<repo>/<name>.tar.gz'
```

## Step 2: Transfer to Remote

遠端檔名每次不同，避免 `/tmp` 裡留著 root 擁有的同名舊檔，導致 scp 失敗、後面讀到舊檔。
記下這個路徑（下稱 `<remote-tar>`），Step 3 與 Cleanup 都用它：

```bash
R=/tmp/<name>.$(date +%s).tar.gz; echo "$R"
SSHPASS='<pw>' sshpass -e scp -o StrictHostKeyChecking=no -o PubkeyAuthentication=no \
  <local-path>.tar.gz <user>@<host>:"$R"; echo "scp=$?"
```

## Step 3: Import and Extract Binary

binary 在 image 裡與在 host 上的路徑不一定同名，兩個都從 unit 的 `nerdctl cp` 那行讀：
`nerdctl cp <extractor>:<in-image-path> <host-path>`（host 那側若是 `.new` 暫存檔再 `mv`，`<host-path>` 取 `mv` 的目的地）。
實例（2026-10-11 在 192.168.6.100）：manager 是 `/usr/local/bin/agent` → `/usr/local/bin/agent`；
console 是 `/usr/local/bin/server` → `/usr/local/bin/arx-console`。

```bash
gunzip -c <remote-tar> | nerdctl -n default load
nerdctl rm -f <extractor-name>
nerdctl create --network=none --name <extractor-name> <image>:<tag>
B=/tmp/<service>-new.$(date +%s); echo "$B"   # 記下這個路徑（下稱 <new-binary>），Step 4 與 Cleanup 用它
nerdctl cp <extractor-name>:<in-image-path> "$B"
nerdctl rm <extractor-name>
```

## Step 4: Stop Service, Replace Binary, Add Override

```bash
systemctl stop <service>
cp <host-path> <host-path>.bak
cp <new-binary> <host-path>
chmod +x <host-path>

# Skip ExecStartPre to prevent image re-extraction overwriting our binary
mkdir -p /etc/systemd/system/<service>.service.d
cat > /etc/systemd/system/<service>.service.d/skip-extract.conf << 'EOF'
[Service]
ExecStartPre=
EOF
systemctl daemon-reload
```

## Step 5: Start and Verify

```bash
systemctl start <service>
systemctl is-active <service>
# Verify via service-specific health endpoint if available
```

## Cleanup After Testing

1. Remove systemd override: `rm /etc/systemd/system/<service>.service.d/skip-extract.conf && systemctl daemon-reload`
2. Restore original binary: `cp <host-path>.bak <host-path>`
3. Restart service (will re-extract from image): `systemctl restart <service>`
4. Clean up tarball and extracted binary: `rm <remote-tar> <new-binary>`（只刪這兩個路徑，不用萬用字元——/tmp 裡可能有別人的檔）

## Units That Run the Container Directly

`ExecStart=nerdctl run … <image>` 的 unit（arx-hal、arx-discover）。換的是 image，不是 binary：
把測試 image 打上一個新 tag，用 drop-in 讓 unit 跑那個 tag。原本的 image 與 tag 都不動，
所以還原只要拿掉 drop-in，不必重新 pull。

1. 照 Step 1–2 build、匯出、傳到遠端，然後載入並打 tag。`<unit-image>` 是 `systemctl cat` 裡
   `ExecStart` 最後那個 image 去掉 tag 的部分：

   ```bash
   gunzip -c <remote-tar> | nerdctl -n default load
   nerdctl -n default tag <image>:<tag> <unit-image>:<version>-dev
   ```

2. 寫 drop-in 覆蓋 `ExecStart`。先一行空的 `ExecStart=` 清掉原值，再把 `systemctl cat` 裡的
   `ExecStart` **整段照抄**（所有 `-v`、`--privileged`、`--network` 等旗標），只換最後的 image：

   ```bash
   mkdir -p /etc/systemd/system/<service>.service.d
   cat > /etc/systemd/system/<service>.service.d/dev-image.conf << 'EOF'
   [Service]
   ExecStart=
   ExecStart=nerdctl run \
       <照抄原本的旗標> \
       <unit-image>:<version>-dev
   EOF
   systemctl daemon-reload
   systemctl restart <service>
   ```

3. 確認跑的是測試版：`nerdctl -n default inspect <container-name> --format '{{.Config.Image}}'`
   要印出 `-dev` 那個 tag。`<container-name>` 是 `ExecStart` 裡 `--name` 的值。

Cleanup：

```bash
rm /etc/systemd/system/<service>.service.d/dev-image.conf && systemctl daemon-reload
systemctl restart <service>
nerdctl -n default inspect <container-name> --format '{{.Config.Image}}'   # 要印回原本的 image
nerdctl -n default rmi <unit-image>:<version>-dev
rm <remote-tar>
```

## Detecting Mock Binary

Some host services have mock build tags (e.g., `mockdbus`, `mocknft`) that replace real system calls with no-ops. If a dev build with these tags is deployed, operations like power commands (reboot/shutdown) and firewall changes silently succeed without doing anything.

**Detection**: check service startup log for mock-related messages:
```bash
journalctl -u <service> | grep -i "mock"
```

Also check for override files in `/etc/systemd/system/<service>.service.d/` — if an override clears `ExecStartPre=`, the binary is not being re-extracted from the container image on restart.
