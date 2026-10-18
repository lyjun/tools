"""Routing eval cases for the personal skill set.

Each case is (prompt, graders). Graders only look at which Skill calls fired and in
what order; run.py assembles the plugin and runs `claude plugin eval` over them.
Pairs follow ~/.claude/rules/routing.md: tracing vs debug is the one either/or
boundary; groundwork and x-plan co-fire (groundwork first); x-design-dialogue is
called by groundwork as a step, so only standalone discussions expect it directly.
A bug ticket that only asks for the cause stays with debug / tracing; groundwork
waits until a found root cause turns into a code change.
"""

def fired(skill):  # tool_use anchor; rules text in hook output never has this shape
    return r'"name":"Skill","input":\{"skill":"(?:[\w-]+:)?' + skill + '"'

def tu(skill, lo=1, hi=None):
    s = f"---\ntype: tool_used\ntool: Skill\ninput_match: '\"skill\"\\s*:\\s*\"(?:[\\w-]+:)?{skill}\"'\nmin: {lo}\n"
    if hi is not None: s += f"max: {hi}\narm: both\n"
    return s + "---\n"

def order(first, second, absent=False):
    m = "not_contains" if absent else "contains"
    return f"---\ntype: regex\ntarget: trace\nmatch: {m}\n---\n{fired(first)}[\\s\\S]*{fired(second)}\n"

TR, DB, GW, PL, DD = "x-code-analysis-tracing", "x-debug-system", "arx-groundwork", "x-plan", "x-design-dialogue"
CG = "x-cc-config-guide"
CASES = {
  # tracing vs debug: the one either/or boundary
  "td-tracing-why-code": ("為什麼 arx-platform-manager 在 RAID reset 之後，會把 md 成員底下的舊 ext4 露出來？從 code 解釋這條路徑。",
      {"tracing-fired": tu(TR), "debug-quiet": tu(DB, 0, 0)}),
  "td-tracing-regression": ("arx-platform-core 的 reboot API 最近回應要 6 秒。幫我從 code 和 git 歷史分析這是哪個改動引入的，不用上機器。",
      {"tracing-fired": tu(TR), "debug-quiet": tu(DB, 0, 0)}),
  "td-tracing-design": ("core 和 manager 各有一份 Docker Hub quota gate，一個 fail-closed 一個 fail-open。為什麼當初不共用？這個 helper 該抽出來嗎？",
      {"tracing-fired": tu(TR), "debug-quiet": tu(DB, 0, 0)}),
  "td-debug-service": ("dev1 上的 arx-platform-manager.service 從昨天升級後就起不來，systemctl status 顯示 failed。幫我查一下。",
      {"debug-fired": tu(DB), "no-tracing-before-debug": order(TR, DB, absent=True)}),
  "td-debug-network": ("192.168.6.31 那台從早上開始 ping 得到，但 ssh 連不上，port 22 直接 timeout。幫我看看怎麼了。",
      {"debug-fired": tu(DB), "no-tracing-before-debug": order(TR, DB, absent=True)}),
  "td-debug-bug-link": ("ardge-labs/ARX-bug#412：裝置升級到 0.7.1 之後 chronyd 沒起來，系統時間差了 3 小時。幫我查原因。",
      {"debug-fired": tu(DB), "no-tracing-before-debug": order(TR, DB, absent=True), "groundwork-quiet": tu(GW, 0, 0)}),
  # groundwork + plan: both load, groundwork first. The sandbox has no shell, so groundwork
  # halts at fetching the issue and x-plan is unreachable; grade only the order guard.
  "gp-spec-issue-plan": ("這是 ardge-labs/ardge-project-issues#901 的內容：\n\n> ## Specification\n> 見 #870。\n> ## Description\n> web UI 加網卡 MTU 設定，manager 端要支援 PUT。\n\n幫我規劃怎麼做、拆成幾張 PR。",
      {"groundwork-fired": tu(GW), "no-plan-before-groundwork": order(PL, GW, absent=True)}),
  "gp-bug-implement": ("ardge-labs/ARX-bug#455：Finder 掛 SMB 時中文檔名變亂碼，issue 裡寫了 relation 到 #440。幫我規劃修法，然後開始動工。",
      {"groundwork-fired": tu(GW), "no-plan-before-groundwork": order(PL, GW, absent=True)}),
  "gp-bug-rootcause-fix": ("ardge-labs/ARX-bug#412 的根因查到了：0.7.1 的 overlay 把 /etc/chrony/chrony.conf 蓋回預設。開始修吧。",
      {"groundwork-fired": tu(GW), "no-plan-before-groundwork": order(PL, GW, absent=True)}),
  "gp-bug-user-rootcause-file": ("ARX-bug#412 chronyd 沒起來，我看是 unit 少了 After=time-sync.target，直接幫我改那個 unit 檔。",
      {"groundwork-fired": tu(GW)}),
  "gp-pure-query": ("ardge-labs/ardge-project-issues#901 目前 assign 給誰？只要告訴我名字。",
      {"groundwork-quiet": tu(GW, 0, 0), "plan-quiet": tu(PL, 0, 0)}),
  # design dialogue
  "dd-discuss-skill": ("先別動手，討論一下：x-plan 產出的 PLAN.md 要不要拆成「計畫」跟「日誌」兩個檔？你覺得怎麼做比較好？",
      {"dialogue-fired": tu(DD), "groundwork-quiet": tu(GW, 0, 0)}),
  "dd-no-spec-feature": ("幫 web UI 的 SSH 設定頁加一個 idle timeout 選項。沒有規格文件，欄位名稱跟上下限你看著辦。",
      {"groundwork-fired": tu(GW)}),
  "dd-mechanical-rename": ("把 arx-platform-manager 裡所有 FirmwareManager 改名成 Manager，同一個機械變換，沒有要討論的。",
      {"dialogue-quiet": tu(DD, 0, 0), "groundwork-quiet": tu(GW, 0, 0)}),
  # config guide: any file under a skill, not only SKILL.md
  "cg-edit-skill-reference": ("在 ~/.claude/skills/x-coding-standards/references/rest-api.md 的 Pagination Modes 那節，補上 pageSize 要有上限的說明。",
      {"guide-fired": tu(CG)}),
  "cg-edit-skill-script": ("~/.claude/skills/x-pr-review/scripts/pr-size.sh 的檔頭註解太長，幫我精簡成三行。",
      {"guide-fired": tu(CG)}),
  "cg-edit-skill-md": ("在 ~/.claude/skills/x-plan/SKILL.md 加一段：拆單時每個項目要寫完成判準。",
      {"guide-fired": tu(CG)}),
}
