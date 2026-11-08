# Remote SSH with Password Credentials

## 強制原則

當使用者提供遠端主機的密碼認證資訊（帳號 + 密碼，不論格式），**必須**直接使用 `sshpass`：

```bash
SSHPASS='<password>' sshpass -e ssh -o StrictHostKeyChecking=no <user>@<host> "<cmd>"
```

**不得**先嘗試無密碼 `ssh`，原因：密碼認證不支援非互動模式，必然失敗。

## 認證資訊來源

IP 與帳號密碼按以下優先序取得（高 → 低）：

1. 當前 session 的使用者訊息（inline 提供）
2. Plan document
3. `~/.config/arx/hosts.yaml`（使用者主動維護的 ARX host config，詳見 `arx-host-config.md`）
4. 全部 miss → 問使用者

其他原則：

- **嚴禁**使用 MEMORY.md 中的 IP / credentials（可能已過期）
- **嚴禁**將 credentials 寫入 MEMORY.md 或任何由 AI 主動建立的持久化檔案
- `~/.config/arx/hosts.yaml` 由使用者主動維護，可讀；連線失敗時**不可**由 AI 自行修改它，請使用者更新
- 首次連線前先用 `ping` 或 `nc -z <host> <ssh_port>` 確認可達性（不送密碼）

## 複雜指令處理

SSH 內嵌多層引號（python、jq、JSON patch）容易逸出失敗。優先使用 heredoc 寫入遠端腳本再執行：

```bash
SSHPASS='<password>' sshpass -e ssh -o StrictHostKeyChecking=no <user>@<host> 'bash -s' << 'REMOTE_EOF'
# 腳本內容，無需擔心引號逸出
kubectl get pods -o jsonpath='{.items[0].metadata.name}'
python3 -c "import sys; print(sys.version)"
REMOTE_EOF
```

**不得**在 `ssh "..."` 內嵌套多層引號後反覆嘗試修正。

### Heredoc Permission Denied Fallback

當 `sshpass ... ssh ... 'bash -s' << 'EOF'` 失敗於 `Permission denied`，**不要**重試同樣的 heredoc。這通常是 SSH key 協商干擾了 heredoc 模式的密碼認證。

**立即 fallback**：改用單行指令，或 SCP 傳腳本檔：

```bash
SSHPASS='<pw>' sshpass -e scp -o PubkeyAuthentication=no script.sh user@host:/tmp/
SSHPASS='<pw>' sshpass -e ssh -o PubkeyAuthentication=no user@host "bash /tmp/script.sh"
```

heredoc 若間歇失敗也適用——只要失敗過一次，當次 session 後續一律改用 SCP。

前提是同一組密碼的單行登入成功過。單行登入也回 `Permission denied`（sshpass exit 5）就是密碼不對，照〈等機器重開〉的認證失敗處理，不換寫法重試。

### Python 解析腳本不要嵌在 bash -c 內

`python3 -c "..."` 內含 dict 操作、f-string、nested quotes 時，**禁止**嵌在 SSH `sudo bash -c '...'` heredoc 內——多層引號逸出會反覆觸發 `SyntaxError: unexpected character after line continuation character`，每次重試都不會成功。

**正確做法**：遠端用 `curl > /tmp/<file>` 落地資料，再用 SSH 外層或本機 `python3` 處理：

```bash
# 遠端只負責產資料
SSHPASS='<pw>' sshpass -e ssh ... 'echo pw | sudo -S bash -c "
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
curl -s http://127.0.0.1:9093/api/v2/alerts > /tmp/am.json
chmod 644 /tmp/am.json
"'

# 解析在 SSH 外層或本機做
SSHPASS='<pw>' sshpass -e ssh ... 'echo pw | sudo -S cat /tmp/am.json' | python3 << 'PY'
import json, sys
d = json.load(sys.stdin)
...
PY
```

簡單一行的 `python3 -m json.tool` 或單變數印出可以保留 inline；超過此複雜度就 SCP / 落地。

## 批次唯讀檢查（mandatory）

對遠端機器做多個獨立的 read-only check（status / log / verify），**必須**合成一個 `ssh ... 'bash -s' << 'EOF' ... EOF` heredoc 一次送過去，不要每個 check 開一次 SSH 連線。

每次 SSH 連線含 TCP + SSH handshake + auth ~1-2s RTT。10 個獨立 check 串行 SSH = 10-20s 純連線浪費。對 fail2ban 保護的 host 還要額外間隔避免被擋，實際更慢。

```bash
# ❌ 浪費（10+ SSH 連線）
SSHPASS="$PW" sshpass -e ssh user@host 'systemctl is-active foo'
SSHPASS="$PW" sshpass -e ssh user@host 'systemctl is-active bar'
SSHPASS="$PW" sshpass -e ssh user@host 'ip -4 -o addr show'

# ✓ 一次 SSH 跑完
SSHPASS="$PW" sshpass -e ssh user@host 'bash -s' << 'EOF'
echo "=== foo ==="
systemctl is-active foo
echo "=== bar ==="
systemctl is-active bar
echo "=== addr ==="
ip -4 -o addr show
EOF
```

例外：需要根據前一個 check 結果決定下一步（dependent check）才分開。純並列 read-only check 一律合併。

## 等機器重開（mandatory）

等遠端機器重開回來時，輪詢迴圈裡**不得**出現 `ssh`／`sshpass`——每一圈只用 `nc -z -G 5 <host> <ssh_port>` 看 port（SSH port 不一定是 22，先確認）：先等到 port 掉（跑滿次數仍沒掉就停下回報，不往下走），再等 port 回來。之後只登入**一次**讀 boot_id（重開後要做的第一批唯讀檢查併進同一個 heredoc），這次登入不丟 stderr、不接 pipe，`$?` 單獨一行。拿到新 boot_id 才算完成；拿到舊的回到「等 port 掉」；其他任何結果（sshpass exit 5 認證失敗、空輸出、連線錯誤）都停下交給使用者，不再試。認證失敗後，這組 credential 在本 session 對這台 host 視為失效：之後對它的任何 ssh／scp（不論指令內容、是否還在等重開）都不得再用，`.last-success` 命中它也一樣。credential 來自 `arx-host-config.md`〈#3〉的清單時，清單裡其他 credential 照 #3 各試一次；其餘情況只能用使用者在失敗之後提供的新密碼（回覆裡給的，或更新後的 hosts.yaml）。

理由：重開過程中可用的密碼可能和重開前不同，迴圈每一圈登入就是一次認證失敗；host 若跑 fail2ban，幾分鐘內就累積到門檻、封鎖本機 IP。port 檢查不送密碼。

```bash
# ❌ 每一圈都登入
for i in $(seq 1 60); do SSHPASS="$PW" sshpass -e ssh user@host 'cat /proc/sys/kernel/random/boot_id'; sleep 10; done

# ✓ 先等 port 掉、再等 port 回來，回來後只登入一次，結果完整留下（run_in_background：總長可能超過 600 秒）
PORT=22   # 以這台的實際 SSH port 為準；舊 boot_id 在下 reboot 前先讀好
LOG=/tmp/bootid.$$.log
down=0; for i in $(seq 1 60); do nc -z -G 5 host "$PORT" || { down=1; break; }; sleep 5; done
[ "$down" = 1 ] || { echo "port 沒掉，停下回報"; exit 1; }
up=0; for i in $(seq 1 120); do nc -z -G 5 host "$PORT" && { up=1; break; }; sleep 5; done
[ "$up" = 1 ] || { echo "port 沒回來，停下回報"; exit 1; }
SSHPASS="$PW" sshpass -e ssh -p "$PORT" user@host 'cat /proc/sys/kernel/random/boot_id' > "$LOG" 2>&1
echo "exit=$?"; cat "$LOG"
```

## 遠端檔案傳輸

結構化內容（YAML、JSON、scripts）超過 10 行時，**禁止**在 SSH heredoc 內嵌套第二層 heredoc（外層會截斷內層）。改用：本地寫檔 → `scp` 傳輸 → 遠端操作。

## sudo 使用（強制）

Heredoc 內需要 root 權限時，**必須**用 `echo <password> | sudo -S`：

```bash
echo <password> | sudo -S kubectl get pods 2>/dev/null
echo <password> | sudo -S bash -c 'KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm list 2>&1'
```

**禁止**使用 `sudo bash -c '...'`（無 `-S`）——SSH heredoc 沒有 TTY，必然觸發 `sudo: a terminal is required`。

### sudo -S 與 stdin 重導衝突

`echo <password> | sudo -S <cmd>` 透過 stdin 餵密碼。當 `<cmd>` 本身又需要從 stdin 讀資料（pipe、process substitution、heredoc、`-i -`）時，兩個來源衝突，密碼會被資料蓋掉，sudo 失敗。

**會踩雷的寫法**：

```bash
# ❌ gunzip 的 stdin 蓋掉密碼，sudo 失敗
echo "$PW" | sudo -S nerdctl load < <(gunzip -c /tmp/img.tar.gz)

# ❌ pipe 後 stdin 已被 cat 取代，密碼進不去 sudo
gunzip -c /tmp/img.tar.gz | sudo -S nerdctl load

# ❌ heredoc 內想 sudo 讀 stdin
echo "$PW" | sudo -S tee /etc/file <<EOF
content
EOF
```

**正確做法**：把資料先落地到檔案，sudo 直接讀檔，stdin 只留給密碼：

```bash
# ✓ 先解壓到檔案，再用 -i 讀檔
gunzip -kf /tmp/img.tar.gz
echo "$PW" | sudo -S nerdctl load -i /tmp/img.tar

# ✓ tee 讀檔內容
echo "content" > /tmp/data
echo "$PW" | sudo -S tee /etc/file < /tmp/data
```

判斷準則：`sudo -S` 後接的 `<cmd>` 若**自己有 stdin 需求**（`<`、`<<`、`<()`、被 pipe 餵資料），就需要把資料先落地。
