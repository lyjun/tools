#!/usr/bin/env python3
"""Extract the actionable parts of an /insights report for x-session-learning --review.

Measures only: which report was read, its section ids, every copy-button item
(text = what the button copies), the Key pattern, Tool Errors counts, and the
full text of section-friction. Judging coverage / adoption stays with the agent.

Every exit path prints one `VERDICT:` line:
  ok           exit 0  all structural expectations met
  error        exit 1  bad usage (the caller's invocation is wrong)
  unavailable  exit 2  preceded by `PROBLEMS:`; each line starts with a tag:
                         [missing]  no report file at all
                         [partial]  N of M items bad, N < M
                         [shape]    an expected section / element / button
                                    shape is absent, or every item is bad
                         [crash]    unhandled exception in this script
"""
import argparse
import datetime as dt
import glob
import os
import sys
from html.parser import HTMLParser

REQUIRED_SECTIONS = ["section-usage", "section-friction", "section-features",
                     "section-patterns", "section-horizon"]
# Copy buttons this script knows how to read. Anything else is a format change.
DEFAULT_DIR = os.path.expanduser("~/.claude/usage-data")
KNOWN_ONCLICK = ("copyCmdItem(", "copyText(this)", "copyAllCheckedClaudeMd(")


def verdict(v, code, reason=""):
    print(f"VERDICT: {v}" + (f" — {reason}" if reason else ""))
    sys.exit(code)


def fail(lines, reason):
    print("PROBLEMS:")
    for x in lines:
        print(f"  - {x}")
    verdict("unavailable", 2, reason)


def pick_report(d):
    stamped = sorted(glob.glob(os.path.join(d, "report-*.html")), key=os.path.getmtime)
    if stamped:
        return stamped[-1]
    plain = os.path.join(d, "report.html")
    return plain if os.path.exists(plain) else None


class Report(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.sections = []          # (id, title)
        self.section = None         # current section id
        self.in_h2 = False
        self.items = []             # (section, kind, text)
        self.unknown_buttons = []   # (section, onclick)
        self.orphan_copytext = []   # copyText button whose previous sibling is not <code>
        self.text_by_section = {}
        self.code_depth = 0
        self.code_buf = []
        self.last_closed = None     # tag name of the element that closed right before
        self.key_pattern = None
        self.in_key = False
        self.key_depth = 0
        self.key_buf = []
        self.chart_title_next = False
        self.chart_title = None
        self.bar_label = None
        self.cur_class = None
        self.tool_errors = []       # (label, value)
        self.tool_errors_found = False
        self.orphan_labels = []     # bar-label with no bar-value before the next label

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = a.get("class", "") or ""
        if tag == "h2" and (a.get("id") or "").startswith("section-"):
            self.section = a["id"]
            self.in_h2 = True
            self.sections.append([a["id"], ""])
        if tag == "input" and "cmd-checkbox" in cls.split():
            self.items.append((self.section, "claude-md", a.get("data-text") or ""))
        if tag == "button":
            onclick = a.get("onclick") or ""
            is_copy = "copy" in cls.lower() or "copy" in onclick.lower()
            if is_copy:
                if onclick.startswith("copyText(this)"):
                    if self.last_closed == "code":
                        self.items.append((self.section, "code", "".join(self.code_buf).strip()))
                    else:
                        self.orphan_copytext.append((self.section, self.last_closed))
                elif not onclick.startswith(KNOWN_ONCLICK):
                    self.unknown_buttons.append((self.section, onclick or f"class={cls}"))
        if tag == "code":
            if self.code_depth == 0:
                self.code_buf = []
            self.code_depth += 1
        if tag == "div" and self.in_key:
            self.key_depth += 1
        if tag == "div" and "key-insight" in cls.split() and self.section == "section-usage":
            self.in_key, self.key_buf, self.key_depth = True, [], 1
        self.cur_class = cls
        if tag == "div" and cls == "chart-title":
            self.chart_title_next = True
        self.last_closed = None

    def handle_endtag(self, tag):
        if tag == "h2":
            self.in_h2 = False
        if tag == "code" and self.code_depth:
            self.code_depth -= 1
        if tag == "div" and self.in_key:
            self.key_depth -= 1
            if self.key_depth == 0:
                self.in_key = False
                self.key_pattern = " ".join("".join(self.key_buf).split())
        self.last_closed = tag

    def handle_data(self, data):
        if self.in_h2 and self.sections:
            self.sections[-1][1] += data.strip()
        if self.code_depth:
            self.code_buf.append(data)
        if self.in_key:
            self.key_buf.append(data)
        if self.section:
            self.text_by_section.setdefault(self.section, []).append(data)
        if self.chart_title_next and data.strip():
            self.chart_title = data.strip()
            self.chart_title_next = False
            self.tool_errors_found |= self.section == "section-usage" and self.chart_title.startswith("Tool Errors")
        in_tool_chart = self.section == "section-usage" and (self.chart_title or "").startswith("Tool Errors")
        if in_tool_chart and data.strip():
            if self.cur_class == "bar-label":
                if self.bar_label:
                    self.orphan_labels.append(self.bar_label)
                self.bar_label = data.strip()
            elif self.cur_class == "bar-value" and self.bar_label:
                self.tool_errors.append((self.bar_label, data.strip()))
                self.bar_label = None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=DEFAULT_DIR)
    ap.add_argument("--report", help="explicit report path (default: newest report-*.html, else report.html)")
    try:
        args = ap.parse_args()
    except SystemExit:
        verdict("error", 1, "bad arguments")
    if not args.dir.strip():
        verdict("error", 1, "--dir given but empty")
    if args.dir != DEFAULT_DIR and not os.path.isdir(args.dir):
        verdict("error", 1, f"--dir {args.dir} is not a directory")
    if args.report is not None and not args.report.strip():
        verdict("error", 1, "--report given but empty")

    if args.report:
        path = args.report
        if not os.path.isfile(path):
            verdict("error", 1, f"--report {path} is not a readable file")
    else:
        path = pick_report(args.dir)
        if not path:
            fail([f"[missing] no report-*.html or report.html under {args.dir}"], "no report")
    print(f"REPORT: {path}")
    print(f"REPORT_MTIME: {dt.datetime.fromtimestamp(os.path.getmtime(path)):%Y-%m-%d %H:%M}")

    p = Report()
    with open(path, encoding="utf-8") as f:
        p.feed(f.read())

    print("SECTIONS:")
    for sid, title in p.sections:
        print(f"  {sid} = {title}")

    problems = []
    found = {s for s, _ in p.sections}
    for s in REQUIRED_SECTIONS:
        if s not in found:
            problems.append(f"[shape] missing section id {s}")
    if not p.items:
        problems.append("[shape] 0 copy-button items extracted")
    for sec, onclick in p.unknown_buttons:
        problems.append(f"[shape] unrecognized copy button in {sec}: {onclick}")
    for sec, prev in p.orphan_copytext:
        problems.append(f"[shape] copyText button in {sec} not preceded by <code> (previous element: {prev})")
    empty = [i for i in p.items if not i[2]]
    if empty:
        tag = "shape" if len(empty) >= len(p.items) else "partial"
        problems.append(f"[{tag}] {len(empty)}/{len(p.items)} copy-button items with empty text")
    if not p.key_pattern:
        problems.append("[shape] Key pattern (div.key-insight in section-usage) not found")
    if not p.tool_errors_found:
        problems.append("[shape] Tool Errors chart (chart-title 'Tool Errors…' in section-usage) not found")
    elif not p.tool_errors:
        problems.append("[shape] Tool Errors chart found but 0 bar rows read")
    if p.bar_label:  # last label never got a value
        p.orphan_labels.append(p.bar_label)
    if p.orphan_labels:
        n, m = len(p.orphan_labels), len(p.orphan_labels) + len(p.tool_errors)
        tag = "shape" if n >= m else "partial"
        problems.append(f"[{tag}] {n}/{m} Tool Errors rows have a label but no value (e.g. {', '.join(p.orphan_labels[:3])})")
    friction = " ".join("".join(p.text_by_section.get("section-friction", [])).split())
    if not friction:
        problems.append("[shape] section-friction has no text")

    print(f"ITEMS: {len(p.items)}")
    for n, (sec, kind, text) in enumerate(p.items, 1):
        print(f"--- item {n} [{sec}] ({kind})")
        print(text)
    print(f"KEY_PATTERN: {p.key_pattern}")
    print("TOOL_ERRORS: " + ", ".join(f"{l}={v}" for l, v in p.tool_errors))
    print("FRICTION_SECTION:")
    print(friction)

    if problems:
        fail(problems, f"{len(problems)} check(s) failed")
    verdict("ok", 0, f"{len(p.items)} items, {len(p.tool_errors)} tool-error rows")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # any crash must still end in a VERDICT line, never a bare traceback
        fail([f"[crash] {type(e).__name__}: {e}"], f"unhandled {type(e).__name__}")
