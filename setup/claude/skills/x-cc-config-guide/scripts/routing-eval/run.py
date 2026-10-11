#!/usr/bin/env python3
"""Run the routing eval: assemble a throwaway plugin from ~/.claude, run the cases, report.

The eval sandbox seals HOME, so personal skills and rules are not loaded on their
own. This script symlinks ~/.claude/skills/* into the plugin's skills/ and injects
~/.claude/CLAUDE.md plus ~/.claude/rules/*.md through a SessionStart hook, so the
child routes the way a real session does. --no-rules drops the hook to measure
description-only routing. --overlay DIR measures a draft before it is written:
DIR/skills/<name>/SKILL.md and DIR/rules/<file>.md replace the live files in the
assembled plugin only.

Routing outcome is the `PASSED: n/m cases` line. The last line is always
`VERDICT: ok|unavailable|error` and says only whether the measurement is valid:
  ok          every run loaded all linked skills (and, with rules, the rules text)
  unavailable a run errored, a trace could not be read, a linked skill was missing
              from the child's skill list, the rules hook carried no rules, or no
              case ran: the PASSED line is not trustworthy
  error       bad usage, or `claude plugin eval` produced no result file
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
CLAUDE = os.path.expanduser("~/.claude")
PLUGIN = "routing-eval"
SKILL_CALL = re.compile(r'"name":"Skill","input":\{"skill":"(?:[\w-]+:)?([\w-]+)"')
KEPT = re.compile(r"kept (/private/tmp/e-[A-Za-z0-9]+)")

HOOK = r'''#!/usr/bin/env python3
import glob, json, os
root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
paths = [os.path.join(root, "context", "CLAUDE.md")] + sorted(glob.glob(os.path.join(root, "context", "rules", "*.md")))
parts = []
for p in paths:
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            parts.append("Contents of " + p + ":\n\n" + f.read())
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "\n\n".join(parts)}}))
'''

def verdict(v, code):
    print(f"VERDICT: {v}")
    sys.exit(code)

def overlay_files(overlay):
    """Map each overlay file to the live file it replaces; a path with no live
    counterpart is a typo that would silently measure the unchanged version."""
    pairs = []
    for p in sorted(glob.glob(os.path.join(overlay, "skills", "*", "SKILL.md")) + glob.glob(os.path.join(overlay, "rules", "*.md"))):
        live = os.path.join(CLAUDE, os.path.relpath(p, overlay))
        if not os.path.exists(live):
            print(f"--overlay: {p} has no live counterpart {live}", file=sys.stderr); verdict("error", 2)
        pairs.append((p, live))
    if not pairs:
        print(f"--overlay: no skills/<name>/SKILL.md or rules/*.md under {overlay}", file=sys.stderr); verdict("error", 2)
    return pairs

def build(root, rules, overlay=None):
    os.makedirs(os.path.join(root, ".claude-plugin"))
    with open(os.path.join(root, ".claude-plugin", "plugin.json"), "w") as f:
        json.dump({"name": PLUGIN, "version": "0.0.0", "description": "routing eval", "skills": "./skills"}, f)
    pairs = overlay_files(overlay) if overlay else []
    over_skills = {os.path.basename(os.path.dirname(p)): p for p, _ in pairs if os.sep + "skills" + os.sep in p}
    over_rules = [p for p, _ in pairs if os.sep + "rules" + os.sep in p]
    sk = os.path.join(root, "skills"); os.makedirs(sk)
    names = []
    for d in sorted(glob.glob(os.path.join(CLAUDE, "skills", "*", "SKILL.md"))):
        n = os.path.basename(os.path.dirname(d)); names.append(n)
        if n in over_skills:  # real copy, then the draft SKILL.md on top
            shutil.copytree(os.path.dirname(d), os.path.join(sk, n))
            shutil.copy(over_skills[n], os.path.join(sk, n, "SKILL.md"))
        else:
            os.symlink(os.path.dirname(d), os.path.join(sk, n))
    for p, live in pairs: print("overlay:", live, "<-", p)
    if rules:
        ctx = os.path.join(root, "context"); os.makedirs(ctx)
        if over_rules:
            shutil.copytree(os.path.join(CLAUDE, "rules"), os.path.join(ctx, "rules"))
            for p in over_rules: shutil.copy(p, os.path.join(ctx, "rules", os.path.basename(p)))
        else:
            os.symlink(os.path.join(CLAUDE, "rules"), os.path.join(ctx, "rules"))
        if os.path.exists(os.path.join(CLAUDE, "CLAUDE.md")):
            os.symlink(os.path.join(CLAUDE, "CLAUDE.md"), os.path.join(ctx, "CLAUDE.md"))
        hk = os.path.join(root, "hooks"); os.makedirs(hk)
        with open(os.path.join(hk, "inject-rules.py"), "w") as f: f.write(HOOK)
        os.chmod(os.path.join(hk, "inject-rules.py"), 0o755)
        with open(os.path.join(hk, "hooks.json"), "w") as f:
            json.dump({"hooks": {"SessionStart": [{"hooks": [{"type": "command",
                "command": '"${CLAUDE_PLUGIN_ROOT}"/hooks/inject-rules.py'}]}]}}, f)
    sys.path.insert(0, HERE)
    from cases import CASES
    for name, (prompt, graders) in CASES.items():
        g = os.path.join(root, "evals", name, "graders"); os.makedirs(g)
        with open(os.path.join(root, "evals", name, "prompt.md"), "w") as f:
            f.write("---\nmax_turns: 8\ntimeout_seconds: 300\nallowed_tools: [Read, Glob, Grep, Skill]\n---\n\n" + prompt + "\n")
        for gn, body in graders.items():
            with open(os.path.join(g, gn + ".md"), "w") as f: f.write(body)
    return names

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--case", default=None, help="case name glob")
    ap.add_argument("--model", default="claude-opus-5-5")
    ap.add_argument("--max-cost-usd", default="10")
    ap.add_argument("--no-rules", action="store_true", help="description-only routing (no rules injected)")
    ap.add_argument("--keep", action="store_true", help="keep the assembled plugin dir")
    ap.add_argument("--overlay", default=None, help="dir with skills/<name>/SKILL.md and/or rules/*.md drafts that replace the live files")
    try: a = ap.parse_args()
    except SystemExit: verdict("error", 2)
    if a.runs < 1: print("--runs must be >= 1", file=sys.stderr); verdict("error", 2)
    for flag, v in (("--case", a.case), ("--model", a.model), ("--max-cost-usd", a.max_cost_usd), ("--overlay", a.overlay)):
        if v is not None and not v.strip():
            print(f"{flag} is empty", file=sys.stderr); verdict("error", 2)

    work = tempfile.mkdtemp(prefix="routing-eval-")
    root = os.path.join(work, "plugin")
    names = build(root, rules=not a.no_rules, overlay=a.overlay)
    out = os.path.join(work, "result.json"); log = os.path.join(work, "eval.log")
    cmd = ["claude", "plugin", "eval", root, "--runs", str(a.runs), "--ablation", "none", "--no-publish",
           "--trust-plugin", "--keep-temp", "--model", a.model, "-j", "4", "--max-cost-usd", a.max_cost_usd, "--json", out]
    if a.case: cmd += ["--case", a.case]
    print("plugin:", root, "| skills linked:", len(names), "| rules:", "off" if a.no_rules else "on")
    print("cmd:", " ".join(cmd))
    with open(log, "w") as lf:
        try: rc = subprocess.call(cmd, stdout=lf, stderr=subprocess.STDOUT)
        except FileNotFoundError: print("claude not on PATH", file=sys.stderr); verdict("error", 2)
    print("eval exit:", rc, "| log:", log)
    if not os.path.exists(out):
        print(open(log).read()[-2000:]); verdict("error", 2)
    d = json.load(open(out))
    print("claude", d.get("claudeVersion"), "| model", a.model, "| cost $%.2f" % d.get("costUsd", 0))

    broken = []; ok_cases = 0
    for c in d.get("cases", []):
        runs = c["arms"]["with"]
        passed = sum(1 for r in runs if r.get("passed"))
        ok_cases += passed == len(runs)
        print(f'\n{c["name"]}: {passed}/{len(runs)} passed')
        for i, r in enumerate(runs, 1):
            seq, loaded, hooked = [], None, False
            try:
                for l in open(r["tracePath"]):
                    seq += SKILL_CALL.findall(l)
                    if '"subtype":"init"' in l:
                        loaded = {s.split(":", 1)[1] for s in json.loads(l).get("skills", []) if s.startswith(PLUGIN + ":")}
                    if '"subtype":"hook_response"' in l and "routing.md" in l: hooked = True
            except Exception as e:
                broken.append(f'{c["name"]}#{i}: trace unreadable ({e.__class__.__name__})')
            if r.get("error"): broken.append(f'{c["name"]}#{i}: {r["error"]}')
            missing = sorted(set(names) - (loaded or set()))
            if missing: broken.append(f'{c["name"]}#{i}: {len(names) - len(missing)}/{len(names)} skills loaded, missing {", ".join(missing)}')
            if not a.no_rules and not hooked: broken.append(f'{c["name"]}#{i}: rules hook carried no routing.md')
            fails = [g["name"] for g in r.get("graders", []) if g.get("scored", True) and not g["passed"]]
            print(f'  run {i}: {" -> ".join(seq) or "(no skill)"}' + (f'   FAIL {", ".join(fails)}' if fails else ""))
    if not d.get("cases"): broken.append("no cases ran")
    cleanup(log, root, a.keep)
    print(f"\nPASSED: {ok_cases}/{len(d.get('cases', []))} cases (a case passes when every run passes)")
    if broken:
        print("not measured:"); [print("  " + b) for b in broken]
        verdict("unavailable", 3)
    verdict("ok", 0)

def cleanup(log, root, keep):
    # --keep-temp leaves each run's sealed (mode 000) sandbox behind; traces are read by now.
    try:
        for k in sorted(set(KEPT.findall(open(log).read()))):
            for dp in (k, os.path.join(k, "sealed")): os.chmod(dp, 0o700)
            shutil.rmtree(k, ignore_errors=True)
    except OSError as e:
        print(f"cleanup: {e}", file=sys.stderr)
    if not keep: shutil.rmtree(root, ignore_errors=True)

try:
    main()
except SystemExit:
    raise
except Exception:
    traceback.print_exc()
    verdict("error", 2)
