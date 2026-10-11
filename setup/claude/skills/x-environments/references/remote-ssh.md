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
- 首次連線前先執行 `ping` 或簡單 SSH 測試確認可達性

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
