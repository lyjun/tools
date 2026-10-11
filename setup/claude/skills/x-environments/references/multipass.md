# Multipass VM

## stop 與 start 分成兩次呼叫

`multipass stop` 和 `multipass start` 不要寫在同一次 Bash 呼叫裡（`&&`、`;` 或其他串接方式都算），分成兩次 tool call、放在兩則訊息裡送出。

Multipass 要一段時間才把資源釋放完；串在一起送，VM 會卡在 Starting 狀態。
