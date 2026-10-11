#!/usr/bin/env python3
"""pr-state.py — the facts two different gates need about a PR, without deciding either.

Two callers ask different questions off the same probe:

  * the liveness gate — "can this code still change, and is there anything new since I
    last engaged?"  It reads STATE and HEAD_CHANGED, and FROZEN is its own conclusion,
    so this script does state that one.
  * the dispatch — "is this my PR, a first review, or a reply-confirmation?"  It reads
    AUTHOR, ME_ENGAGED and HEAD_CHANGED and decides for itself.  This script deliberately
    does NOT emit a case label: fl-arx-pr-review requires that dispatch make that call
    from the live probe, and a CASE field here would be exactly the pre-decision it
    forbids.

Why SHA and not timestamps.  "Has anything landed since my review" was previously judged
by comparing commit dates against the review's date.  `committedDate` is the commit's own
date, not the push time, so an author who wrote a commit before the review and pushed it
after produces commit dates that are all older — and the gate reports nothing new while
the code did change.  Each review record carries the `commit_id` it was written against,
so comparing that against the current head answers the question outright.  Measured on a
live PR while writing this: reviewed at dcf60e63, head now 1b41b362.

Engagement is read from three buckets, because a prior review lands in whichever the
convention put it: review bodies, issue comments, and inline review comments.  An empty
`reviews` array does not mean you have not reviewed this PR.

Usage:
    pr-state.py <owner>/<repo>#<num> [<owner>/<repo>#<num> ...] [--repo PATH] [--checks]

    --repo PATH   a local clone, used only to answer whether the commit you reviewed is
                  still reachable (a force-push can orphan it, which decides whether an
                  incremental re-review is even possible). It applies to the PR whose repo
                  name matches the path's basename; for the others the answer is reported
                  as unknown rather than guessed.

    --checks      also read the live CI state of the head commit: per-bucket counts, the
                  names still running, the names failing, and whether the run has settled.
                  A PR description saying "tests all green" is the author's claim about
                  some earlier commit; this reads what the head actually reports.

Why --checks is a measurement and not a green light.  It never says "safe to approve" —
it reports counts and names, and SETTLED is recomputed from them.  The one thing it
refuses to do is call an empty answer clean: a query that fails, or that returns fewer
runs than the API's own total_count, reports `unavailable`, because "no checks came back"
and "no checks are failing" are indistinguishable in the output that bit us — a poll loop
read an empty result as a completed run and reported every PR settled while all of them
were still building.

Exit: 0 ok · 1 usage · 3 a PR could not be read, or --checks was asked for and could not
be answered (no verdict available for it)
"""

import json
import re
import subprocess
import sys

PR_RE = re.compile(r"^([^/]+)/([^#]+)#(\d+)$")


def gh(*args):
    """Return parsed JSON, or None when the call fails. Never raises on a failed call."""
    try:
        out = subprocess.run(
            ["gh", "api", *args], capture_output=True, text=True, timeout=60
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return None


def excerpt(body):
    """First non-empty line, trimmed — enough to tell a review from a drive-by question."""
    for line in (body or "").splitlines():
        line = line.strip()
        if line:
            return line[:100] + ("…" if len(line) > 100 else "")
    return "(no body)"


def reachable(repo, sha, pr_repo_name):
    """Answer only for the repo the PR actually lives in.

    --repo is a single path while the PR list can span repos, so a global flag is right
    for at most one of them. Answering "no" for the others would report a force-push that
    never happened — worse than not answering, because it reads as a fact.
    """
    if not sha:
        return "n/a (never engaged, or my trace carries no commit_id)"
    if not repo:
        return "unknown (no --repo)"
    import os

    if os.path.basename(os.path.normpath(repo)) != pr_repo_name:
        return f"unknown (--repo is {os.path.basename(os.path.normpath(repo))}, not {pr_repo_name})"
    r = subprocess.run(
        ["git", "-C", repo, "cat-file", "-e", f"{sha}^{{commit}}"],
        capture_output=True,
    )
    return "yes" if r.returncode == 0 else "no (force-pushed, or simply not fetched here)"


# A check run's conclusion decides its bucket. Anything not yet completed is pending,
# whatever its conclusion field says. `cancelled` sits with the failures on purpose: a run
# that was killed produced no answer, and treating "no answer" as an answer is the whole
# failure this flag exists to prevent.
PASS_CONCLUSIONS = {"success", "neutral"}
SKIP_CONCLUSIONS = {"skipped"}


def checks(owner, name, sha):
    """Bucket the head commit's check runs and legacy statuses.

    Returns (buckets, pending_names, failing_names, problem). `problem` is non-empty when
    the answer is untrustworthy, and the caller must then report unavailable rather than
    read the buckets — an empty bucket set is produced both by "nothing is wrong" and by
    "nothing came back", and only `problem` separates them.
    """
    buckets = {"pass": 0, "fail": 0, "pending": 0, "skipping": 0}
    pending, failing = [], []

    runs = gh(f"repos/{owner}/{name}/commits/{sha}/check-runs", "-X", "GET",
              "-f", "per_page=100")
    if runs is None:
        return buckets, pending, failing, "check-runs query failed"
    listed = runs.get("check_runs") or []
    total = runs.get("total_count")
    if isinstance(total, int) and total != len(listed):
        # Same cross-check pr-files.sh runs: a silently truncated page reads as a shorter,
        # cleaner run. Refuse rather than bucket a partial list.
        return buckets, pending, failing, f"only {len(listed)} of {total} check runs listed"

    for r in listed:
        label = r.get("name") or "(unnamed)"
        if r.get("status") != "completed":
            buckets["pending"] += 1
            pending.append(label)
        elif r.get("conclusion") in SKIP_CONCLUSIONS:
            buckets["skipping"] += 1
        elif r.get("conclusion") in PASS_CONCLUSIONS:
            buckets["pass"] += 1
        else:
            buckets["fail"] += 1
            failing.append(f"{label} ({r.get('conclusion')})")

    # Legacy commit statuses are a separate surface; a repo can report CI through either.
    st = gh(f"repos/{owner}/{name}/commits/{sha}/status")
    if st is None:
        return buckets, pending, failing, "commit-status query failed"
    for s in st.get("statuses") or []:
        label = s.get("context") or "(unnamed status)"
        state = s.get("state")
        if state == "pending":
            buckets["pending"] += 1
            pending.append(label)
        elif state == "success":
            buckets["pass"] += 1
        else:
            buckets["fail"] += 1
            failing.append(f"{label} ({state})")

    if sum(buckets.values()) == 0:
        # Genuinely ambiguous: a repo with no CI, and a push whose workflows have not been
        # created yet, look identical here. Neither may be reported as settled.
        return buckets, pending, failing, "no check runs or statuses on this commit"
    return buckets, pending, failing, ""


def report(owner, name, num, me, local_repo, want_checks=False):
    slug = f"{owner}/{name}#{num}"
    pr = gh(f"repos/{owner}/{name}/pulls/{num}")
    if pr is None:
        print(f"=== {slug} ===")
        print("ERROR: could not read the PR")
        print("VERDICT: unavailable")
        return 3

    reviews = gh(f"repos/{owner}/{name}/pulls/{num}/reviews", "--paginate") or []
    issue_comments = gh(f"repos/{owner}/{name}/issues/{num}/comments", "--paginate") or []
    inline_comments = gh(f"repos/{owner}/{name}/pulls/{num}/comments", "--paginate") or []

    state = pr.get("state", "?").upper()
    if pr.get("merged_at"):
        state = "MERGED"
    head_sha = (pr.get("head") or {}).get("sha", "")
    author = (pr.get("user") or {}).get("login", "?")

    # Every trace of mine, from all three buckets, with the sha the review saw.
    mine = []
    for r in reviews:
        if (r.get("user") or {}).get("login") == me:
            mine.append((r.get("submitted_at") or "", excerpt(r.get("body")),
                         r.get("commit_id") or "", "review"))
    for c in issue_comments:
        if (c.get("user") or {}).get("login") == me:
            mine.append((c.get("created_at") or "", excerpt(c.get("body")), "", "comment"))
    for c in inline_comments:
        if (c.get("user") or {}).get("login") == me:
            mine.append((c.get("created_at") or "", excerpt(c.get("body")),
                         c.get("commit_id") or "", "inline"))
    mine.sort()

    engaged = bool(mine)
    engaged_at = mine[-1][0] if engaged else ""
    engaged_excerpt = mine[-1][1] if engaged else ""
    engaged_kind = mine[-1][3] if engaged else ""
    # The sha to compare against is the newest one any of my traces recorded.
    reviewed_sha = next((m[2] for m in reversed(mine) if m[2]), "") if engaged else ""

    if not engaged:
        head_changed = "n/a (never engaged)"
    elif not reviewed_sha:
        head_changed = "unknown (my trace carries no commit_id)"
    else:
        head_changed = "no" if reviewed_sha == head_sha else f"yes ({reviewed_sha[:8]} → {head_sha[:8]})"

    # Anyone else's comment after my last trace is also something new to act on.
    others_after = 0
    if engaged_at:
        for c in issue_comments + inline_comments:
            login = (c.get("user") or {}).get("login")
            when = c.get("created_at") or ""
            if login and login != me and when > engaged_at:
                others_after += 1

    if state != "OPEN":
        frozen = "yes (state is not OPEN — the code is frozen)"
    elif not engaged:
        frozen = "no (never engaged)"
    elif head_changed == "no" and others_after == 0:
        frozen = "yes (engaged, head unchanged, no replies since)"
    else:
        frozen = "no (something landed after my last trace)"

    print(f"=== {slug} ===")
    print(f"STATE: {state}")
    print(f"IS_DRAFT: {'yes' if pr.get('draft') else 'no'}")
    print(f"AUTHOR: {author}")
    print(f"ME: {me}")
    print(f"ME_ENGAGED: {'yes' if engaged else 'no'}"
          + (f" (via {engaged_kind}; {len(mine)} trace(s) total)" if engaged else ""))
    print(f"ENGAGED_AT: {engaged_at or '-'}")
    print(f"ENGAGED_EXCERPT: {engaged_excerpt or '-'}")
    print(f"REVIEWED_SHA: {reviewed_sha[:12] if reviewed_sha else '-'}")
    print(f"HEAD_SHA: {head_sha[:12]}")
    print(f"HEAD_CHANGED: {head_changed}")
    print(f"REVIEWED_SHA_REACHABLE: {reachable(local_repo, reviewed_sha, name)}")
    print(f"REPLIES_AFTER_ME: {others_after}")
    print(f"FROZEN: {frozen}")

    rc = 0
    if want_checks:
        buckets, pending, failing, problem = checks(owner, name, head_sha)
        if problem:
            print(f"CHECKS: unavailable ({problem})")
            print("CHECKS_SETTLED: unknown")
            rc = 3
        else:
            print(f"CHECKS: {sum(buckets.values())} total — {buckets['pass']} pass, "
                  f"{buckets['fail']} fail, {buckets['pending']} pending, "
                  f"{buckets['skipping']} skipping")
            print(f"CHECKS_PENDING: {', '.join(pending) if pending else '-'}")
            print(f"CHECKS_FAILING: {', '.join(failing) if failing else '-'}")
            print("CHECKS_SETTLED: "
                  + ("yes" if buckets["pending"] == 0 else f"no ({buckets['pending']} still running)"))

    print("NOTE: no case label here — dispatch decides 2a vs 2b from AUTHOR + ME_ENGAGED + HEAD_CHANGED")
    return rc


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if argv else 1

    prs, local_repo, want_checks, i = [], "", False, 0
    while i < len(argv):
        if argv[i] == "--checks":
            want_checks = True
            i += 1
            continue
        if argv[i] == "--repo":
            if i + 1 >= len(argv):
                print("ERROR: --repo needs a value")
                print("VERDICT: error")
                return 1
            # Explicit emptiness check: an empty --repo value would otherwise be
            # indistinguishable from the flag never being passed, and the script would
            # silently answer "unknown (no --repo)" for a caller that did name one.
            if not argv[i + 1].strip():
                print("ERROR: --repo was given an empty value")
                print("VERDICT: error")
                return 1
            local_repo = argv[i + 1]
            i += 2
            continue
        m = PR_RE.match(argv[i])
        if not m:
            print(f"ERROR: '{argv[i]}' is not <owner>/<repo>#<num>")
            print("VERDICT: error")
            return 1
        prs.append(m.groups())
        i += 1

    if not prs:
        print("usage: pr-state.py <owner>/<repo>#<num> [...] [--repo PATH]")
        print("VERDICT: error")
        return 1

    who = gh("user", "--jq", ".login")
    me = who if isinstance(who, str) else None
    if not me:
        r = subprocess.run(["gh", "api", "user", "--jq", ".login"],
                           capture_output=True, text=True)
        me = r.stdout.strip()
    if not me:
        print("ERROR: could not resolve your own login — engagement cannot be judged")
        print("VERDICT: unavailable")
        return 3

    worst = 0
    for owner, name, num in prs:
        rc = report(owner, name, num, me, local_repo, want_checks)
        worst = max(worst, rc)
        print()
    # An unreadable PR and an unanswerable --checks both land here: the caller asked a
    # question that did not get answered, and reporting ok would let the empty answer pass
    # as a clean one. Read this line, not the shell's status.
    print(f"VERDICT: {'ok' if worst == 0 else 'unavailable'} — {len(prs)} PR(s) probed"
          + (" (--checks)" if want_checks else ""))
    return worst


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
