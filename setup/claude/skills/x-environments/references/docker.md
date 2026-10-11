# Docker 操作規範

## Output 控制（強制）

Docker 相關指令（build、save、import、push 等）輸出量大，必須限制進入 context 的 output：

- **背景執行**：長時間指令用 `run_in_background`，完成後從 output file 取需要的部分
- **成功路徑**：`tail -5 <output_file>` 確認結果
- **失敗路徑**：`grep -i "error\|fail" <output_file>` 提取關鍵錯誤
- **完整 log**：僅在上述方式無法定位問題時才讀取更多

## 重試策略

- 同一錯誤連續失敗 2 次 → 停下來告知使用者，不繼續消耗 token

## 容器對外連線掛住（不是失敗）

容器內對外的 HTTPS 掛住不回、而 DNS 秒回、TCP 握手也成功時，先比對兩個 MTU。
這不是唯一可能的成因（proxy 靜默丟包、OCSP 查詢卡住都有同樣形狀），但它最便宜，
兩條指令就有答案：

```bash
route -n get default | grep interface        # default route 的出口卡
ifconfig <那張卡> | grep mtu                  # 路徑 MTU
docker run --rm alpine ip link show eth0     # 容器宣告的 MTU（需 daemon 已啟動）
```

容器的比路徑的小或相等就不是這個問題。比較大時，容器在 SYN 裡宣告的 MSS 沒有把
路徑的窄段算進去，對方於是退回自己那端的上限（一般是 1460，也就是 1500-byte 的
封包），那個大小過不了窄的那一段；要讓對方縮小 segment 的 ICMP 是送給**對方**的
（不是送進容器），沿途被濾掉時對方就一路重傳到逾時，所以症狀是掛住而不是報錯。
繞法是讓容器一開始就宣告小一點的 MSS——自建一個限制 MTU 的 network，並在呼叫點
指定它：

```bash
docker network create --opt com.docker.network.driver.mtu=1400 mtu1400
docker run --rm --network mtu1400 ...
```

1400 只是留了餘裕的常見值，不是通用答案；真正的上限是上面量到的路徑 MTU。

`docker run` 的呼叫點常常不在手上——藏在 Makefile 的變數、compose 的 service、
devcontainer.json 的 `runArgs` 裡。要改的是那個呼叫點，不是另外開一條指令。
Makefile 的情況用命令列賦值蓋掉即可（命令列優先於檔案裡的定義，`=` 與 `:=`
都一樣）：`make <target> <變數名>='docker run … --network mtu1400 …'`。

一次性設定的方向是 `~/.docker/daemon.json` 加 `"mtu": 1400`，讓預設 bridge 與之後
新建的 network 都繼承，不必改每個呼叫點。未驗：沒在這台機器上試過，Docker Desktop
是否吃這個鍵也還沒查證，而且它要重啟 daemon（會帶走正在跑的容器）。

devcontainer 走 dind，最內層仍是同一個容器，換進 devcontainer 不會改變這件事。

**host 上同一個 URL 通，不證明容器那條路通**：host 可能經由別的 transport 到達
（例如 git 的 `insteadof` 改走 SSH），根本沒有走到出問題的那條路徑。拿 host 的成功
當對照組會把方向帶去「容器沒網路」。

量到過的一個實例（macOS + Docker Desktop，2026-09）：出口卡 1492（PPPoE），而預設
bridge 上容器的 `eth0` 是 65535——不是常見的 1500，所以「看起來像 1500 應該還好」
這個直覺在這裡不成立。改走 1400 的自建 network 後同一個 `git ls-remote` 立刻回。
