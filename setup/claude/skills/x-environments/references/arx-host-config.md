# ARX Host Config

當使用者用 alias（例：「連到 dev」、「登入開發機」）指涉 ARX 主機時，先讀 `~/.config/arx/hosts.yaml` 解析 IP 與 credentials，再交給 `remote-ssh.md` 的 SSH 流程。

## 設定檔位置

- 路徑：`~/.config/arx/hosts.yaml`
- 權限：`chmod 600` — 讀取前確認；若 mode > 600 警告使用者並建議修正
- YAML 解析工具：`yq`（mikefarah/yq）

## Schema

```yaml
version: 1

credentials:
  <credential_id>:
    aliases: [<alias1>, <alias2>, ...]    # 使用者可能用的短稱
    user: <os_username>
    password_b64: <base64_of_password>

hosts:
  <host_id>:
    aliases: [<alias1>, <alias2>, ...]
    ip: <ip_or_hostname>
    credentials: [<cred_id_1>, <cred_id_2>, ...]   # retry 順序
```

## Credential 解析優先序（高 → 低）

| # | 來源 | 觸發條件 |
|---|---|---|
| 1 | **Inline 對話提供** | 使用者訊息含 `id/pw` / `user xxx password xxx` 等 |
| 2 | **明示 credential**（從 config） | 「用 `<credential_alias>` 連到 `<host_alias>`」 |
| 3 | **Host 的 retry list**（從 config） | 「連到 `<host_alias>`」，未指定 credential |
| 4 | **問使用者** | 全部 miss |

Cache hint 只作用於 #3。

## Host alias 解析

對輸入字串 `X`，依序比對：

1. host canonical id（YAML map key）
2. 各 host 的 `aliases` 陣列

第一個命中即用；多重命中 → 問使用者選哪個。

## Credential alias 解析

對輸入字串 `Y`，依序比對：

1. credential canonical id
2. 各 credential 的 `aliases` 陣列
3. credential 的 `user` 欄位（fallback）

第一個命中即用；多重命中 → 問使用者選哪個。

## #3 Retry 行為（無明示 credential）

1. 讀 `~/.config/arx/.last-success`，找該 host 上次成功的 credential
2. 若 cache 有：先試該 credential
3. Cache miss 或 cache 試完失敗：依 `host.credentials[]` 順序逐一試
4. 每次失敗間隔 1-2 秒（避免觸發 fail2ban / IDS）
5. 第一個成功 → 連線、更新 cache
6. 全部失敗 → 列出試過的 credentials，請使用者更新 config 或提供 inline credentials

## #2 Hard-fail（使用者明示 credential）

使用者明指 credential 時（「用 X 帳號」、`--as X`），若該 credential 認證失敗：

- **禁止** fallback 到其他 credentials
- 報錯：「Credential `<name>` 認證失敗。請確認 `~/.config/arx/hosts.yaml` 內的密碼或機器狀態。」
- 等待使用者指令

原因：使用者明指 = 他**就要那個身份**（權限、家目錄、ownership 都跟身份綁）。靜默 fallback 會讓使用者以為登入成功是 X，實際是別人，後續操作可能寫錯位置或無權限。

## Hybrid：config host + inline credentials

使用者同時提供 alias **與** inline credentials：

> 「連到 dev，用 `ardge / mypass`」

- IP 從 config 取（host 查表）
- Credentials 用 inline（#1 優先序）
- **不更新 cache**（inline 是一次性）

## 純 inline（不碰 config）

使用者給完整 IP + credentials，沒提到任何 alias：

- 跳過 config 查表，走 `remote-ssh.md`
- **不主動詢問是否存進 config**（使用者已決定 inline 為一次性）

## 設定檔狀態異常處理

| 狀況 | 行為 |
|---|---|
| `~/.config/arx/hosts.yaml` 不存在 | Fallback 問使用者；告知可建立此檔以後不用每次貼 |
| `yq` 解析失敗 | 報錯指出問題行；請使用者修正 |
| `password_b64` 解碼失敗 | 跳過該 credential，試下一個；warning log |
| 權限過鬆（mode > 600） | 警告 + 建議 `chmod 600`；仍可繼續使用 |

## Cache 檔

- 路徑：`~/.config/arx/.last-success`
- 格式：YAML，`<host_canonical_id>: <credential_canonical_id>`
- 更新時機：**僅** #3 模式（retry list）連線成功時更新
- 不更新：#1（inline）、#2（明示 credential）

範例：

```yaml
arx-dev-yijyun: yijyun-personal
arx-new-001: factory-default
```

## 查表 / 取值範本

讀 host IP：

```bash
yq '.hosts.arx-dev-yijyun.ip' ~/.config/arx/hosts.yaml
```

依 alias 查 host canonical id：

```bash
yq '.hosts | to_entries | map(select(.value.aliases[] == "dev" or .key == "dev")) | .[0].key' \
  ~/.config/arx/hosts.yaml
```

取 credential 並解碼密碼：

```bash
user=$(yq '.credentials.yijyun-personal.user' ~/.config/arx/hosts.yaml)
pw=$(yq '.credentials.yijyun-personal.password_b64' ~/.config/arx/hosts.yaml | base64 -d)
SSHPASS="$pw" sshpass -e ssh -o StrictHostKeyChecking=no "$user"@<ip> "<cmd>"
```

⚠️ **不要**用 `sshpass -p "$pw"` —— `ps` 看得到。一律 `SSHPASS=... sshpass -e`。
