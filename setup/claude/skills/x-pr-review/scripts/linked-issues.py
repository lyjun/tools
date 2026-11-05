#!/usr/bin/env python3
"""linked-issues.py — which issues a PR description links to, and how far their threads run.

An issue's body is a snapshot of the day it was filed. What happened after — the root
cause someone found, the fix they settled on, a deployment precondition such as "needs a
re-initialisation", a tester's readings from a real machine — lands in the comments. A
review that opens the issue and stops at the body reasons from that snapshot. This script
prints the comment count and the newest comment's time for every linked issue, so the
reviewer's "read up to comment K of K" line has a number to match. Readings often sit not in
the comment text but in a file it links to (an evidence file, a screenshot, a log), so it also
lists every link in the comments (`attachments=N`, one `ATTACHMENT:` line each) for the
reviewer's "opened A of A" to match.

It reads the PR description only — never the PR's own reviews or comments — so it is safe
to run when those must stay unread (a review replayed against an older head).

GitHub's own link fields cannot be used: a description that names an issue in prose, or in
another repository, leaves `closingIssuesReferences` and the cross-reference timeline empty.
So the links are pulled out of the description text.

Usage:
    linked-issues.py <owner>/<repo>#<num> [--body-file PATH]

    --body-file PATH   read the description from this file instead of the PR (a snapshot);
                       <owner>/<repo>#<num> still resolves bare `#N` and `repo#N` references
                       and is excluded from the results.

Recognised forms: https://github.com/<owner>/<repo>/(issues|pull)/<N>, <owner>/<repo>#<N>,
<repo>#<N> (owner taken from the PR), and bare #<N> (same repository).

Exit / VERDICT: 0 ok (also when no link is found — the line says so) · 1 error (usage) ·
3 unavailable (the description, or any linked issue, could not be read).
"""

import json
import re
import subprocess
import sys

PR_RE = re.compile(r"^([^/\s]+)/([^#\s]+)#(\d+)$")
URL_RE = re.compile(r"https://github\.com/([\w.-]+)/([\w.-]+)/(?:issues|pull)/(\d+)(?![\w/-])")
# owner/repo#N or repo#N; the lookbehind keeps it from starting mid-word or inside a URL path.
REF_RE = re.compile(r"(?<![\w/.-])(?:([\w.-]+)/)?([\w.-]*[A-Za-z][\w.-]*)#(\d+)\b")
# bare #N: preceded by start, whitespace or an opening bracket — not "##", not an anchor.
BARE_RE = re.compile(r"(?:^|(?<=[\s(\[]))#(\d+)\b")
# a link inside a comment body; stops at whitespace, a closing bracket/paren, quotes or '<>'.
LINK_RE = re.compile(r"https?://[^\s)\]<>\"']+")


def gh(*args):
    try:
        out = subprocess.run(["gh", "api", *args], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return None


def find_links(body, owner, repo):
    found = []
    text = body or ""
    for o, r, n in URL_RE.findall(text):
        found.append((o, r, int(n)))
    no_urls = URL_RE.sub(" ", text)
    for o, r, n in REF_RE.findall(no_urls):
        found.append((o or owner, r, int(n)))
    for n in BARE_RE.findall(REF_RE.sub(" ", no_urls)):
        found.append((owner, repo, int(n)))
    seen, out = set(), []
    for o, r, n in found:
        key = (o.lower(), r.lower(), n)
        if key not in seen:
            seen.add(key)
            out.append((o, r, n))
    return out


def find_attachments(comments):
    """Every distinct http(s) URL in the comment bodies, with the 1-based comment it first
    appears in. Evidence files, screenshots and logs are posted as links (a blob URL into a
    repository, an uploaded user-attachment, an image); all links are listed rather than
    guessing which ones are evidence, so the count the reviewer matches is not a judgement."""
    seen, out = set(), []
    for k, c in enumerate(comments, 1):
        for url in LINK_RE.findall(c.get("body") or ""):
            url = url.rstrip(".,;:!?'\"")
            if url not in seen:
                seen.add(url)
                out.append((k, url))
    return out


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if argv else 1

    slug, body_file, i = None, None, 0
    while i < len(argv):
        if argv[i] == "--body-file":
            if i + 1 >= len(argv) or not argv[i + 1].strip():
                print("ERROR: --body-file needs a non-empty value")
                print("VERDICT: error")
                return 1
            body_file = argv[i + 1]
            i += 2
            continue
        if slug is not None:
            print(f"ERROR: unexpected argument '{argv[i]}'")
            print("VERDICT: error")
            return 1
        slug = argv[i]
        i += 1

    m = PR_RE.match(slug or "")
    if not m:
        print(f"ERROR: '{slug}' is not <owner>/<repo>#<num>")
        print("VERDICT: error")
        return 1
    owner, repo, num = m.group(1), m.group(2), int(m.group(3))

    if body_file:
        try:
            with open(body_file, encoding="utf-8") as f:
                body = f.read()
        except OSError as e:
            print(f"ERROR: cannot read --body-file: {e}")
            print("VERDICT: unavailable")
            return 3
        source = f"file {body_file}"
    else:
        pr = gh(f"repos/{owner}/{repo}/pulls/{num}")
        if pr is None:
            print(f"ERROR: could not read {owner}/{repo}#{num}")
            print("VERDICT: unavailable")
            return 3
        body = pr.get("body") or ""
        source = f"PR {owner}/{repo}#{num} description"

    links = [l for l in find_links(body, owner, repo)
             if (l[0].lower(), l[1].lower(), l[2]) != (owner.lower(), repo.lower(), num)]
    print(f"SOURCE: {source} ({len(body.splitlines())} lines)")
    if not links:
        print("LINKED: none found in the description")
        print("VERDICT: ok — 0 linked")
        return 0

    bad = 0
    for o, r, n in links:
        issue = gh(f"repos/{o}/{r}/issues/{n}")
        if issue is None:
            print(f"LINKED: {o}/{r}#{n} — could not read")
            bad += 1
            continue
        kind = "pr" if issue.get("pull_request") else "issue"
        count = issue.get("comments")
        last = "-"
        attached = []
        if isinstance(count, int) and count > 0:
            comments = gh(f"repos/{o}/{r}/issues/{n}/comments", "--paginate")
            if not isinstance(comments, list) or len(comments) != count:
                got = len(comments) if isinstance(comments, list) else "none"
                print(f"LINKED: {o}/{r}#{n} — comment list unreadable ({got} of {count})")
                bad += 1
                continue
            last = comments[-1].get("created_at") or "-"
            attached = find_attachments(comments)
        title = (issue.get("title") or "").strip()
        print(f"LINKED: {o}/{r}#{n} [{kind}, {issue.get('state')}] comments={count} "
              f"last_comment={last} attachments={len(attached)} title={title[:90]}")
        for k, url in attached:
            print(f"  ATTACHMENT: comment {k}: {url}")

    if bad:
        print(f"VERDICT: unavailable — {bad} of {len(links)} linked item(s) unreadable")
        return 3
    print(f"VERDICT: ok — {len(links)} linked")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
