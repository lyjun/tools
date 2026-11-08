#!/usr/bin/env python3
"""PreToolUse hook (matcher: Bash) — turn avoidable permission prompts into a self-correction.

WHY THIS EXISTS
  Claude Code's permission checker cannot analyse some command shapes. When the model writes
  one, the call stops and a dialog waits for the user, even when every command in it is already
  on the allow list (e.g. `Bash(git *)`). Observed dialogs (2026-11-08):
    - "A variable set in this command can't be checked before it runs"
    - "Redirect target concatenation contains $/ — unanalyzable gap or substitution"
    - "A variable in this command can't be checked before it runs"          ($$ in a log path)
    - "Contains brace with quote character (expansion obfuscation)"         (inline python dict)
  The rules already told the model to write values literally and it still did not, so this hook
  enforces it. Upstream position: anthropics/claude-code#86462 (closed not planned) — the
  maintainers call the checker's shape sensitivity intentional and suggest a PreToolUse hook.

WHAT IT DOES
  Runs before the permission check on every Bash call. If the command matches one of the shapes
  below it returns permissionDecision "deny"; the call never runs, the user sees no dialog, and
  the reason text goes to the model, which rewrites the command (one extra tool call).
  Anything else: exit 0 with no output, so normal permission handling applies unchanged.

  1. NAME=<literal value containing '/'> as its own statement, later used as $NAME / ${NAME}
     (paths, scratchpad dirs, branch names). The reason names the literal to substitute.
     Not blocked: NAME=$(...), values containing $ or `, values without '/', and the
     env-prefix form `NAME=value cmd` (e.g. SSHPASS='pw' sshpass ...).
  2. $$ anywhere in a command that does not mention ssh. Locally $$ only names a log path;
     inside an ssh string it expands on the remote host and is left alone.
  3. Inline Python (python3 -c / python3 - / heredoc) containing a brace next to a quote.
     The fix is to write the script to a scratchpad file and run python3 /abs/file.py.

KNOWN LIMITS
  - A heredoc body line like `X=/path` followed by `$X` is blocked even though it is not shell.
  - Loop variables (`for r in a b; do git -C $r`) are not blocked.
  - Shape 3 was inferred from two dialogs only; it may block more or less than the checker.

RELATED
  Rules that teach the literal form: ~/.claude/rules/tool-constraints.md (zsh word-split section,
  >/dev/null section) and ~/.claude/rules/file-operations.md (Search Strategy).
  Registered in ~/.claude/settings.json -> hooks.PreToolUse (matcher "Bash").
  To disable: remove that entry, or run /hooks.
  Test table: feed {"tool_name":"Bash","tool_input":{"command":"..."}} on stdin; deny prints
  JSON, pass prints nothing.
"""
import json
import re
import sys

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


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
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
        deny(
            "Blocked: a variable holding a path or name cannot be checked by the permission "
            "system, so this call would stop and wait for the user. Rewrite the same command with "
            f"the values written out literally and drop the assignment: {subs}. "
            "Keep it one Bash call joined with ';'. " + EXCUSES
        )

    if "$$" in cmd and not re.search(r'(?<![A-Za-z0-9_-])ssh(?![A-Za-z0-9_-])', cmd):
        deny(
            "Blocked: $$ makes the path unreadable to the permission system, so this call would "
            "stop and wait for the user. Locally, redirect to a literal file in this session's "
            "scratchpad directory instead (it is per-session, so no stale file can block the "
            "redirect): e.g. <cmd> >/abs/scratchpad/<step>.log 2>&1; echo \"exit=$?\"; "
            "tail -20 /abs/scratchpad/<step>.log. Keep $$ only inside an ssh command string, "
            "where it expands on the remote host."
        )

    if INLINE_PY.search(cmd) and BRACE_QUOTE.search(cmd):
        deny(
            "Blocked: inline Python with a brace next to a quote ({'k': ...}, f\"{x}\") trips the "
            "permission system's 'brace with quote character' check, so this call would stop and "
            "wait for the user. Write the script to a file in this session's scratchpad directory "
            "with the Write tool, then run it as python3 /abs/scratchpad/<name>.py <args>. "
            "A short one-line python3 -c without braces is fine."
        )
    sys.exit(0)


if __name__ == "__main__":
    main()
