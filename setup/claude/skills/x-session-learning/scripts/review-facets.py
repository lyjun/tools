#!/usr/bin/env python3
"""Aggregate /insights facets for x-session-learning --review.

Measures only: the requested window vs the window the facets actually cover,
per-type friction totals with first/second-half counts, and every session's
friction_counts + friction_detail verbatim. Grouping by theme, coverage and the
trend verdict stay with the agent.

Every exit path prints one `VERDICT:` line:
  ok           exit 0
  error        exit 1  bad usage (the caller's invocation is wrong)
  unavailable  exit 2  preceded by `PROBLEMS:`; each line starts with a tag
                       derived from the counts on that same line:
                         [missing]  the data is not there at all
                         [partial]  N of M items bad, N < M
                         [shape]    every item bad (N == M), or a required
                                    field is absent everywhere
                         [crash]    unhandled exception in this script
"""
import argparse
import collections
import datetime as dt
import glob
import json
import os
import sys


DEFAULT_DIR = os.path.expanduser("~/.claude/usage-data")
MAX_DAYS = 3650


def verdict(v, code, reason=""):
    print(f"VERDICT: {v}" + (f" — {reason}" if reason else ""))
    sys.exit(code)


def fail(lines, reason):
    print("PROBLEMS:")
    for x in lines:
        print(f"  - {x}")
    verdict("unavailable", 2, reason)


def counted(n, total, what, samples=()):
    """Tag by a fixed rule on the printed counts: all bad -> shape, some bad -> partial."""
    tag = "shape" if n >= total else "partial"
    s = f"[{tag}] {n}/{total} {what}"
    if samples:
        s += " (e.g. " + ", ".join(samples[:3]) + ")"
    return s


def parse_ts(s):
    t = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    if t.tzinfo is None:
        raise ValueError("start_time has no timezone")
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, required=False)
    ap.add_argument("--dir", default=DEFAULT_DIR)
    try:
        args = ap.parse_args()
    except SystemExit:
        verdict("error", 1, "bad arguments")
    if not args.dir.strip():
        verdict("error", 1, "--dir given but empty")
    if args.days is None or not 0 < args.days <= MAX_DAYS:
        verdict("error", 1, f"--days N (0 < N <= {MAX_DAYS}) is required")
    if args.dir != DEFAULT_DIR and not os.path.isdir(args.dir):
        verdict("error", 1, f"--dir {args.dir} is not a directory")

    meta_files = sorted(glob.glob(os.path.join(args.dir, "session-meta", "*.json")))
    facet_files = sorted(glob.glob(os.path.join(args.dir, "facets", "*.json")))
    if not facet_files:
        fail([f"[missing] no facets under {args.dir}/facets"], "no facets")
    if not meta_files:
        fail([f"[missing] no session-meta under {args.dir}/session-meta"], "no session-meta")

    problems = []
    start = {}
    bad_meta = []
    for f in meta_files:
        try:
            d = json.load(open(f, encoding="utf-8"))
            sid = d.get("session_id") or os.path.basename(f)[:-5]
            start[sid] = parse_ts(d["start_time"])
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            bad_meta.append(os.path.basename(f))
    if bad_meta:
        problems.append(counted(len(bad_meta), len(meta_files),
                                "session-meta files unreadable or without a timezone-aware start_time", bad_meta))
    if not start:
        fail(problems, "no session-meta has a usable start_time")

    now = dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(days=args.days)
    in_window = {s for s, t in start.items() if t >= cutoff}

    rows = []
    bad_facet, no_meta, no_counts, bad_counts = [], [], [], []
    detail_types = collections.Counter()
    for f in facet_files:
        name = os.path.basename(f)
        try:
            d = json.load(open(f, encoding="utf-8"))
        except (OSError, ValueError):
            bad_facet.append(name)
            continue
        if not isinstance(d, dict):
            bad_facet.append(name)
            continue
        sid = d.get("session_id") or name[:-5]
        if not isinstance(sid, str):
            bad_facet.append(name)
            continue
        if sid not in start:
            no_meta.append(name)
            continue
        if sid not in in_window:
            continue
        counts = d.get("friction_counts")
        if "friction_counts" not in d:
            no_counts.append(name)
            counts = {}
        elif not isinstance(counts, dict):
            bad_counts.append(name)
            counts = {}
        detail_types[type(d.get("friction_detail")).__name__] += 1
        rows.append((start[sid], sid, counts, d.get("friction_detail")))
    if bad_facet:
        problems.append(counted(len(bad_facet), len(facet_files), "facets files unreadable, not a JSON object, or with a non-string session_id", bad_facet))
    if no_meta:
        problems.append(counted(len(no_meta), len(facet_files), "facets files have no matching session-meta (left out)", no_meta))
    if no_counts:
        problems.append(counted(len(no_counts), len(rows), "facets files in the window have no friction_counts field", no_counts))
    no_detail = [sid[:8] for _, sid, c, det in rows if c and not (isinstance(det, str) and det.strip())]
    with_counts = sum(1 for r in rows if r[2])
    if no_detail:
        problems.append(counted(len(no_detail), with_counts, "sessions with friction_counts have no friction_detail text", no_detail))
    if bad_counts:
        problems.append(counted(len(bad_counts), len(rows), "facets files in the window have a friction_counts that is not an object", bad_counts))

    rows.sort()
    print(f"WINDOW_REQUESTED: {args.days} days (since {cutoff:%Y-%m-%d})")
    print(f"SESSIONS: {len(in_window)} in window, {len(rows)} with facets"
          f" (facets without session-meta: {len(no_meta)})")
    if rows:
        lo, hi = rows[0][0], rows[-1][0]
        span = (hi.date() - lo.date()).days + 1  # calendar days, inclusive
        print(f"FACETS_COVER: {lo:%Y-%m-%d %H:%M} .. {hi:%Y-%m-%d %H:%M} UTC ({span} calendar days)")
        if span < args.days:
            print(f"NOTE: facets cover fewer days than requested ({span} < {args.days})")
    print(f"FRICTION_DETAIL_TYPES: {dict(detail_types)}")

    mid = len(rows) // 2
    if rows:
        print(f"HALF_BOUNDARY: first half ends {rows[mid - 1][0]:%Y-%m-%d %H:%M} UTC" if mid else "HALF_BOUNDARY: n/a")
    tot, a, b = collections.Counter(), collections.Counter(), collections.Counter()
    n_values, bad_values = 0, []
    for i, (_, sid, counts, _) in enumerate(rows):
        for k, v in counts.items():
            n_values += 1
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                tot[k] += v
                (a if i < mid else b)[k] += v
            else:
                bad_values.append(f"{sid[:8]}:{k}")
    if bad_values:
        problems.append(counted(len(bad_values), n_values, "friction_counts values are not numbers", bad_values))
    print("FRICTION_TOTALS: type total first second change%")
    for k, v in tot.most_common():
        ch = f"{(b[k] - a[k]) / a[k] * 100:+.0f}%" if a[k] else "n/a"
        print(f"  {k} {v} {a[k]} {b[k]} {ch}")

    print("SESSIONS_DETAIL:")
    for t, sid, counts, detail in rows:
        if not counts:
            continue
        d = detail if isinstance(detail, str) else json.dumps(detail, ensure_ascii=False)
        print(f"- {t:%Y-%m-%d %H:%M} {sid} {json.dumps(counts, ensure_ascii=False)}")
        print(f"  {d}")

    if problems:
        fail(problems, f"{len(problems)} check(s) failed")
    if not rows:
        fail([f"[missing] no facets inside the last {args.days} days"], "no facets in window")
    verdict("ok", 0, f"{len(rows)} sessions, {sum(tot.values())} friction events")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # any crash must still end in a VERDICT line, never a bare traceback
        fail([f"[crash] {type(e).__name__}: {e}"], f"unhandled {type(e).__name__}")
