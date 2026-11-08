#!/usr/bin/env python3
"""PreToolUse hook (matcher: Bash) - settle command shapes the permission checker cannot parse.

WHY THIS EXISTS
  Claude Code's permission checker cannot analyse some command shapes. When the model writes
  one, the call stops and a dialog waits for the user, even when every command in it is already
  on the allow list (e.g. `Bash(git *)`). Observed dialogs (2026-11-08):
    - "A variable set in this command can't be checked before it runs"
    - "Redirect target concatenation contains $/ — unanalyzable gap or substitution"
    - "A variable in this command can't be checked before it runs"          ($$ in a log path)
    - "Contains brace with quote character (expansion obfuscation)"         (inline python dict)
    - "Quoted text in this command can't be checked before it runs"         (F=$(ls ...); grep "$F")
  The set of unanalyzable shapes is undocumented, and upstream (anthropics/claude-code#86462,
  closed not planned) calls the checker's shape sensitivity intentional and suggests a hook.

WHAT IT DOES (checked in this order; the first match decides)
  1. ALLOW - every command in the call, including those inside $(...), is on READ_ONLY and
     nothing writes: no output redirect except 2>&1, no input redirect or heredoc, no backtick,
     no nested $(...), no background `&`, no subshell `( )`, no find action, no sort -o.
     The call runs with no dialog. Verified 2026-11-08: the "Quoted text" dialog above did not
     appear once this returned allow.
  2. DENY with a rewrite instruction - shapes that would stop on a dialog and are not read-only:
     a. NAME=<literal containing '/'> as its own statement, later used as $NAME / ${NAME}.
        Not matched: NAME=$(...), values containing $ or `, values without '/', and the
        env-prefix form `NAME=value cmd` (e.g. SSHPASS='pw' sshpass ...).
     b. $$ in a command that does not mention ssh (locally it only names a log path; inside an
        ssh string it expands on the remote host).
     c. Inline Python (python3 -c / python3 - / heredoc) with a brace next to a quote.
     The call never runs; the reason goes to the model, which rewrites it (one extra tool call).
  3. Anything else: exit 0 with no output, so normal permission handling applies unchanged.

  Why allow is checked first: the deny shapes exist only because they cause a dialog. A
  read-only command no longer causes one, so denying it would cost a turn for nothing.

SAFETY
  - settings.json deny and ask rules are still evaluated after an allow (permissions docs,
    "Precedence among rules, hooks, and mods"), so this cannot override them.
  - Any parse doubt in step 1 falls through to step 2/3, never to allow.
  - If this script crashes it prints nothing, which is step 3: back to the plain dialog.
  - Wider than the Read allow rules: a read-only command reading outside /Users/yijyun and
    /private/tmp (e.g. cat /etc/hosts) is allowed.

KNOWN LIMITS
  - A heredoc body line like `X=/path` followed by `$X` is denied even though it is not shell.
  - Loop variables (`for r in a b; do git -C $r`) are neither allowed nor denied.
  - git and other allow-listed tools are not on READ_ONLY, so their unanalyzable shapes still
    reach the dialog.

RELATED
  Rules that teach the literal form: ~/.claude/rules/tool-constraints.md and
  ~/.claude/rules/file-operations.md. Registered in ~/.claude/settings.json ->
  hooks.PreToolUse (matcher "Bash"). To disable: remove that entry, or run /hooks.
  Test: feed {"tool_name":"Bash","tool_input":{"command":"..."}} on stdin; allow/deny print
  JSON, pass-through prints nothing. Add --explain to see why step 1 passed a command through.
"""
import json
import re
import shlex
import sys

# ---- step 1: read-only approval -------------------------------------------------------------

READ_ONLY = {
    "ls", "head", "tail", "grep", "egrep", "fgrep", "cat", "wc", "sort", "uniq", "echo",
    "printf", "cut", "tr", "basename", "dirname", "stat", "realpath", "readlink", "test",
    "[", "true", "diff", "find",
}
FIND_BAD = {"-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprint0", "-fprintf", "-fls"}
SORT_BAD = re.compile(r"^-(o|-output)")
OPS = {";", "&&", "||", "|"}
LEADING_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PLACEHOLDER = "__RO_SUB__"


class Unsure(Exception):
    pass


def extract_subs(cmd):
    """Replace each top-level $(...) with PLACEHOLDER; return (new_cmd, bodies). No nesting."""
    out, bodies, i, q = [], [], 0, None
    while i < len(cmd):
        c = cmd[i]
        if q == "'":
            out.append(c)
            if c == "'":
                q = None
            i += 1
            continue
        if c == "\\":
            out.append(cmd[i:i + 2])
            i += 2
            continue
        if c == "'" and q is None:
            q = "'"
        elif c == '"':
            q = None if q == '"' else '"'
        if cmd.startswith("$(", i):
            j, bq = i + 2, None
            while j < len(cmd):
                d = cmd[j]
                if bq:
                    if d == bq:
                        bq = None
                elif d in "'\"":
                    bq = d
                elif cmd.startswith("$(", j):
                    raise Unsure("nested substitution")
                elif d == ")":
                    break
                j += 1
            else:
                raise Unsure("unterminated substitution")
            bodies.append(cmd[i + 2:j])
            out.append(PLACEHOLDER)
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out), bodies


def check_pipeline(cmd):
    if "`" in cmd or "<" in cmd or "\n" in cmd:
        raise Unsure("backtick, input redirect, heredoc or newline")
    # Only fd duplication 2>&1 is allowed as a redirect; drop it before lexing.
    cmd = cmd.replace("2>&1", " ")
    if ">" in cmd:
        raise Unsure("output redirect")
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    try:
        tokens = list(lex)
    except ValueError as e:
        raise Unsure(str(e))
    seg = []
    for t in tokens + [";"]:
        if t in OPS:
            check_segment(seg)
            seg = []
        elif set(t) <= set(";&|()"):
            raise Unsure(f"operator {t!r}")
        else:
            seg.append(t)


def check_segment(words):
    while words and LEADING_ASSIGN.match(words[0]):
        words = words[1:]
    if not words:
        return  # pure assignment; a $(...) value was checked as its own pipeline
    name = words[0]
    if name not in READ_ONLY:
        raise Unsure(f"command {name!r}")
    if name == "find" and FIND_BAD & set(words):
        raise Unsure("find action")
    if name == "sort" and any(SORT_BAD.match(w) for w in words):
        raise Unsure("sort -o")


def read_only(cmd):
    """Return None when the whole call is read-only, else the reason it is not."""
    try:
        top, bodies = extract_subs(cmd)
        for b in bodies:
            check_pipeline(b)
        check_pipeline(top)
    except Unsure as e:
        return str(e)
    return None


# ---- step 2: shapes to deny -----------------------------------------------------------------

STMT_START = r'(?:^|[;\n(]|&&|\|\|)[ \t]*'
ASSIGN = re.compile(STMT_START + r'([A-Za-z_][A-Za-z0-9_]*)=(\'[^\']*\'|"[^"]*"|[^\s;&|]*)(?=[ \t]*(?:;|\n|&&|\|\||$))')

INLINE_PY = re.compile(r'(?<![A-Za-z0-9_./-])python3?(?:\s+-[A-Za-z]+)*?\s+(?:-c\b|-(?=\s|$)|<<)')
BRACE_QUOTE = re.compile(r'\{\s*[\'"]|[\'"]\s*\}')

EXCUSES = (
    "Why the variable does not pay off here: "
    "'the path is long' -> it is printed once per line either way, and a literal path lets the "
    "permission check read it, so the call runs without stopping for the user; "
    "'copying it 8 times risks a typo' -> a typo fails loudly on that one line, a variable that "
    "cannot be checked stops the whole call for the user; "
    "'it is cleaner' -> cleanliness of a one-off command is worth less than a prompt the user has to answer."
)


def deny_reason(cmd):
    hits = []
    for m in ASSIGN.finditer(cmd):
        name, raw = m.group(1), m.group(2)
        val = raw[1:-1] if raw[:1] in "'\"" and raw[-1:] == raw[:1] and len(raw) >= 2 else raw
        if not val or "$" in val or "`" in val or "/" not in val:
            continue
        rest = cmd[m.end():]
        if re.search(r'\$(?:\{' + name + r'\}|' + name + r'(?![A-Za-z0-9_]))', rest):
            hits.append((name, val))
    if hits:
        subs = "; ".join(f"replace ${n} (and ${{{n}}}) with {v}" for n, v in hits)
        return (
            "Blocked: a variable holding a path or name cannot be checked by the permission "
            "system, so this call would stop and wait for the user. Rewrite the same command with "
            f"the values written out literally and drop the assignment: {subs}. "
            "Keep it one Bash call joined with ';'. " + EXCUSES
        )

    if "$$" in cmd and not re.search(r'(?<![A-Za-z0-9_-])ssh(?![A-Za-z0-9_-])', cmd):
        return (
            "Blocked: $$ makes the path unreadable to the permission system, so this call would "
            "stop and wait for the user. Locally, redirect to a literal file in this session's "
            "scratchpad directory instead (it is per-session, so no stale file can block the "
            "redirect): e.g. <cmd> >/abs/scratchpad/<step>.log 2>&1; echo \"exit=$?\"; "
            "tail -20 /abs/scratchpad/<step>.log. Keep $$ only inside an ssh command string, "
            "where it expands on the remote host."
        )

    if INLINE_PY.search(cmd) and BRACE_QUOTE.search(cmd):
        return (
            "Blocked: inline Python with a brace next to a quote ({'k': ...}, f\"{x}\") trips the "
            "permission system's 'brace with quote character' check, so this call would stop and "
            "wait for the user. Write the script to a file in this session's scratchpad directory "
            "with the Write tool, then run it as python3 /abs/scratchpad/<name>.py <args>. "
            "A short one-line python3 -c without braces is fine."
        )
    return None


# ---- main -----------------------------------------------------------------------------------

def decide(decision, reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if data.get("tool_name") != "Bash":
        sys.exit(0)
    cmd = (data.get("tool_input") or {}).get("command") or ""

    why_not = read_only(cmd)
    if why_not is None:
        decide("allow", "bash-shape-gate: every command in the call is read-only")
    if "--explain" in sys.argv:
        print(f"not read-only: {why_not}", file=sys.stderr)

    reason = deny_reason(cmd)
    if reason:
        decide("deny", reason)
    sys.exit(0)


if __name__ == "__main__":
    main()
