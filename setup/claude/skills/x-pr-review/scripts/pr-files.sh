#!/usr/bin/env bash
# pr-files.sh — build the coverage list for a PR, with the changedFiles count cross-check.
#
# Replaces the prose that used to warn about `gh pr view --json files` returning at most
# 100 entries with no indication that it truncated. On a 301-file PR it handed back 100
# paths, every one got a disposition, the gate passed, and a clean verdict was issued on a
# third of the diff. The cross-check is arithmetic, so it belongs here: a mismatch exits
# non-zero and no clean verdict is available.
#
# Usage:
#   pr-files.sh <owner>/<repo> <num>                       # normal path
#   pr-files.sh <owner>/<repo> <num> --local PATH --base B --head H
#                                                          # needed above 3000 files
#   pr-files.sh -h | --help                                # print this block
#
# Output: one row per changed file — status, the ref it is readable at, the path — plus a
# blank disposition column for the reviewer to fill. Which ref comes from `status`; the
# disposition (讀過 / 跳過:generated / 跳過:trivial) is a judgement and stays with the
# reviewer.
# Exit:  0 ok · 1 usage · 2 count mismatch (no clean verdict) · 3 list unavailable
#        · 0 with VERDICT: degraded when the status column could not be obtained

set -u

usage_and_exit() {
  # Bounded on the comment block itself, not on hard-coded line numbers: the previous
  # `sed -n '2,20p'` form printed whatever happened to sit at those lines, which after a
  # comment edit was `set -u` and the variable initialisers — source code in a help screen.
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
  exit 0
}

# -h before the argument-count check, and exiting 0: asking for help is not a usage error,
# and a caller keying off the exit code cannot otherwise tell the two apart.
case "${1:-}" in -h|--help) usage_and_exit ;; esac

[ $# -lt 2 ] && { echo "usage: pr-files.sh <owner>/<repo> <num> [--local PATH --base B --head H]"; echo "VERDICT: error"; exit 1; }
OWNER_REPO="$1"; NUM="$2"; shift 2
# bash 3.2 — which is what /usr/bin/env bash resolves to on this machine — returns 1 from
# `shift 2` when only one argument remains AND DOES NOT SHIFT, silently. With no `set -e` the
# loop below then re-tests the same $1 forever: no output, no exit code, no VERDICT line, just
# a spin until something kills it. That is the one failure here a caller cannot name, because
# every contract downstream says to read the VERDICT line. Guard before shifting.
need() { [ "$1" -ge 2 ] || { echo "ERROR: $2 needs a value"; echo "VERDICT: error"; exit 1; }; }

LOCAL=""; BASE=""; HEAD_REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --local) need $# --local; LOCAL="$2"; shift 2 ;;
    --base)  need $# --base; BASE="$2"; shift 2 ;;
    --head)  need $# --head; HEAD_REF="$2"; shift 2 ;;
    -h|--help) usage_and_exit ;;
    *) echo "ERROR: unknown argument '$1'"; echo "VERDICT: error"; exit 1 ;;
  esac
done
# Absolutise the repo path even though everything here only feeds `git -C`, which tolerates
# a relative one. The sibling scripts each had a bug from comparing a path built here
# against a path git returned (git always answers absolute); doing this uniformly is what
# keeps that from arriving the first time someone adds a comparison.
if [ -n "$LOCAL" ]; then
  LOCAL="$(cd "$LOCAL" 2>/dev/null && pwd -P)" || true
  [ -n "$LOCAL" ] || { echo "ERROR: cannot enter the --local path"; echo "VERDICT: error"; exit 1; }
fi

# The authoritative total. `changedFiles` in the same command that truncates `files` to
# 100 reports the true number, which is what makes the truncation visible at all.
TOTAL="$(gh pr view "$NUM" --repo "$OWNER_REPO" --json changedFiles --jq '.changedFiles' 2>/dev/null || true)"
if [ -z "$TOTAL" ] || [ "$TOTAL" = "null" ]; then
  echo "ERROR: could not read changedFiles for $OWNER_REPO#$NUM — the count cross-check cannot run"
  echo "VERDICT: unavailable — no clean verdict is available for this review"
  exit 3
fi
echo "PR: $OWNER_REPO#$NUM"
echo "changedFiles: $TOTAL"

emit() {   # status \t path \t previous_filename
  # The disposition placeholder is written out rather than left as blank space: an
  # unfilled row is then visible on the page instead of having to be remembered.
  awk -F'\t' '
    {
      ref = ($1 == "removed") ? "base" : "head"
      # The former name of a renamed path exists only at base: git show <head>:<old> exits
      # 128. Saying where it is readable stops a reviewer from reading at head and getting
      # nothing back.
      prev = ($3 == "" ? "" : " (was: " $3 " — readable at base only)")
      printf "%-9s read-at:%-5s %s%s  → disposition:___\n", $1, ref, $2, prev
    }'
}

# --- Above 3000 the API itself stops -------------------------------------------
# GitHub caps that endpoint at 3000 entries, --paginate included, so the cross-check
# could never agree and the clean-verdict gate would be permanently closed. Take the
# list from the local clone instead, and say that is where it came from.
if [ "$TOTAL" -gt 3000 ]; then
  if [ -z "$LOCAL" ] || [ -z "$BASE" ] || [ -z "$HEAD_REF" ]; then
    echo "ERROR: $TOTAL files exceeds the API's 3000 cap — rerun with --local PATH --base B --head H"
    echo "VERDICT: unavailable — no clean verdict is available for this review"
    exit 3
  fi
  git -C "$LOCAL" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "ERROR: --local '$LOCAL' is not a git repo"
    echo "VERDICT: unavailable — no clean verdict is available for this review"; exit 3; }
  ROWS="$(git -C "$LOCAL" diff --name-status --find-renames "$BASE...$HEAD_REF" 2>/dev/null | awk -F'\t' 'BEGIN{OFS="\t"}
    { s = $1
      if (s ~ /^R/) print "renamed", $3, $2
      else if (s == "A") print "added", $2, ""
      else if (s == "D") print "removed", $2, ""
      else if (s == "M") print "modified", $2, ""
      else print tolower(s), $2, "" }')"
  # An unresolvable ref makes git diff exit 128 with empty stdout, which the count
  # cross-check below would otherwise report as "likely truncated" — a cause it never
  # checked. Name the real one here.
  if [ -z "$ROWS" ]; then
    echo "ERROR: git diff $BASE...$HEAD_REF in $LOCAL produced nothing — fetch both refs first"
    echo "VERDICT: unavailable — no clean verdict is available for this review"; exit 3
  fi
  echo "source: local clone ($LOCAL), git diff $BASE...$HEAD_REF — the API caps at 3000"
  echo ""
  echo "=== Coverage list (fill the disposition column) ==="
  echo "(status · which ref the path is readable at · path · disposition to fill)"
  printf '%s\n' "$ROWS" | emit
  COUNT="$(printf '%s' "$ROWS" | grep -c . || true)"
else
  # --paginate, and the /files endpoint — not `gh pr view --json files`.
  ROWS="$(gh api "repos/$OWNER_REPO/pulls/$NUM/files" --paginate \
    --jq '.[] | [.status, .filename, (.previous_filename // "")] | @tsv' 2>/dev/null || true)"
  SOURCE="repos/$OWNER_REPO/pulls/$NUM/files --paginate"
  if [ -z "$ROWS" ]; then
    # Documented fallback: no status column, so `removed` cannot be told apart and the
    # base-ref disposition is unavailable. Degraded, and it says so.
    echo "NOTE: the /files API returned nothing (rate limit, network, or access) — falling back to gh pr diff --name-only"
    ROWS="$(gh pr diff "$NUM" --repo "$OWNER_REPO" --name-only 2>/dev/null | awk 'BEGIN{OFS="\t"}{print "unknown", $0, ""}' || true)"
    if [ -z "$ROWS" ]; then
      echo "ERROR: the fallback failed too — the coverage list cannot be built"
      echo "VERDICT: unavailable — no clean verdict is available for this review"
      exit 3
    fi
    DEGRADED="yes"
    # The source line has to name the endpoint the rows actually came from. Printing the
    # /files endpoint on the path taken because that endpoint returned nothing is the same
    # defect class as a verdict stating a cause it never checked.
    SOURCE="gh pr diff --name-only (fallback; /files returned nothing)"
  fi
  echo "source: $SOURCE"
  echo ""
  echo "=== Coverage list (fill the disposition column) ==="
  echo "(status · which ref the path is readable at · path · disposition to fill)"
  printf '%s\n' "$ROWS" | emit
  COUNT="$(printf '%s' "$ROWS" | grep -c . || true)"
fi

echo ""
echo "rows: $COUNT · changedFiles: $TOTAL"
if [ "$COUNT" -ne "$TOTAL" ]; then
  # The cause depends on which source produced the rows, and naming the wrong one sends the
  # reader to the wrong remedy. Truncation is an API-path phenomenon; a local `git diff`
  # does not truncate, so a delta there is rename detection or a different merge-base.
  if [ -n "$LOCAL" ]; then
    echo "VERDICT: count-mismatch — the local diff and GitHub disagree on the count. Not truncation: a local diff does not truncate. Likely rename detection or a merge-base difference — fetch both refs and check that --base is the PR's real base. No clean verdict is available"
  else
    echo "VERDICT: count-mismatch — the list is incomplete (likely truncated); no clean verdict is available"
  fi
  exit 2
fi
if [ "${DEGRADED:-no}" = "yes" ]; then
  echo "VERDICT: degraded — status column unavailable, so 'removed' paths cannot be identified; read-at:head is a guess for every row"
  exit 0
fi
echo "VERDICT: ok — every path is listed; give each exactly one disposition before any verdict"
exit 0
