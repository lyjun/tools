#!/usr/bin/env bash
# range-detect.sh — resolve the review mode, the diff range, and the changed-file list.
#
# Replaces the inline Step 0 + Step 1 scripts that used to live in x-code-review/SKILL.md
# with three model-substituted placeholders (__RANGE__ / __REPO_DIR__ / __FORCE_FULL__).
# The substitution was the variance: filling __REPO_DIR__ with an empty string while cwd
# is not a repo made every bare git call run in the wrong place, and an unnormalised
# two-dot range turned base-side commits into inverted diffs.
#
# Usage:
#   range-detect.sh                          # auto-detect mode + range from cwd
#   range-detect.sh --repo PATH              # cwd is not the repo
#   range-detect.sh --range A..B [--repo P]  # explicit range (forces single-project)
#   range-detect.sh --full [--repo P]        # skip incremental detection
#   range-detect.sh -h | --help              # print this block
#
# Reads:  VERDICT and (git diff exit=N) are in-band; the exit code mirrors VERDICT.
# Exit:   0 ok · 1 usage/validation error · 2 range unresolved · 3 no changed files
#         · 4 cross-repo (caller goes to Step 1X)

set -u

usage_and_exit() {
  # Bounded on the comment block itself, not on hard-coded line numbers: the previous
  # `sed -n '2,20p'` form printed whatever happened to sit at those lines, which after a
  # comment edit was `set -u` and the variable initialisers — source code in a help screen.
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
  exit 0
}

# Two different ways a flag arrives unusable, and both used to pass.
#
# Missing entirely: bash 3.2 — which is what /usr/bin/env bash resolves to on this machine —
# returns 1 from `shift 2` when only one argument remains AND DOES NOT SHIFT, silently. With
# no `set -e` the loop below then re-tests the same $1 forever: no output, no exit code, no
# VERDICT line, just a spin until something kills it. That is the one failure here a caller
# cannot name, because every contract downstream says to read the VERDICT line.
#
# Present but empty: `--range ""` used to fall straight through to auto-detection, so a caller
# that did supply a range had it silently dropped and got `VERDICT: no-changes` off
# develop...HEAD instead. `--repo ""` is worse — from a single-repo cwd it measures a repo the
# caller never named and reports `VERDICT: ok`. Guard both before shifting.
need() {
  [ "$1" -ge 2 ] || { echo "ERROR: $2 needs a value"; echo "VERDICT: error"; exit 1; }
  [ -n "$3" ] || { echo "ERROR: $2 was given an empty value"; echo "VERDICT: error"; exit 1; }
}

REPO=""
EXPLICIT_RANGE=""
FORCE_FULL="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)  need $# --repo "${2:-}"; REPO="$2"; shift 2 ;;
    --range) need $# --range "${2:-}"; EXPLICIT_RANGE="$2"; shift 2 ;;
    --full)  FORCE_FULL="true"; shift ;;
    -h|--help) usage_and_exit ;;
    *) echo "ERROR: unknown argument '$1'"; echo "VERDICT: error"; exit 1 ;;
  esac
done

# --- Mode detection (former Step 0) ---------------------------------------------
# Only runs when the caller did not name a repo. An explicit range is single-project
# by definition, so it never reaches the cross-repo branch: the probe reads cwd only,
# and from a directory holding several repos it would return cross-repo, Step 1X would
# derive its own BASE...HEAD per project, and the range would be silently discarded.
if [ -z "$REPO" ]; then
  if git rev-parse --git-dir >/dev/null 2>&1; then
    REPO="$(git rev-parse --show-toplevel)"
  else
    # No -type d: in a worktree (and a submodule checkout) .git is a FILE holding a
    # "gitdir:" pointer, so -type d finds nothing and the cross-repo layout — the one
    # Step 1X exists for — would come back as unknown.
    # Absolutised, for the same reason PROJECT= is below: this list is handed to a subagent
    # that runs in its own cwd, and `find .` yields ./repo. A relative path there either
    # fails or — with a same-named sibling next to the subagent's cwd — succeeds against
    # the WRONG repo and produces a confident report about unrelated code.
    PROJECTS="$(find . -maxdepth 2 -name .git 2>/dev/null | while read -r d; do (cd "$(dirname "$d")" && pwd -P); done | sort)"
    COUNT="$(printf '%s\n' "$PROJECTS" | grep -c . || true)"
    if [ "$COUNT" -gt 1 ]; then
      if [ -n "$EXPLICIT_RANGE" ]; then
        echo "ERROR: a range was supplied from a directory that merely contains repos."
        echo "       Name the target repo with --repo. Candidates found:"
        printf '%s\n' "$PROJECTS" | sed 's/^/         /'
        echo "VERDICT: error"
        exit 1
      fi
      echo "MODE=cross-repo"
      echo "PROJECTS:"
      printf '%s\n' "$PROJECTS"
      echo "VERDICT: cross-repo"
      exit 4
    elif [ "$COUNT" -eq 1 ]; then
      REPO="$(cd "$PROJECTS" && pwd)"
    else
      echo "MODE=unknown — cwd is not a repo and holds none"
      echo "VERDICT: error"
      exit 1
    fi
  fi
fi

cd "$REPO" || { echo "ERROR: cannot cd into '$REPO'"; echo "VERDICT: error"; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: '$REPO' is not a git repo"; echo "VERDICT: error"; exit 1; }
# Absolutise before printing. PROJECT= is handed to a subagent that runs in its own cwd, so a
# relative --repo (which is what a cross-repo project list yields: ./arx-platform-core) would
# reach it as a path that resolves to nothing there.
REPO="$(pwd -P)"

echo "MODE=single-project"
echo "PROJECT=$REPO"

# --- Range normalisation and validation ----------------------------------------
# Two-dot compares the two endpoints, so once the left side has advanced past the
# branch point its own commits appear as inverted diffs. Normalising here rather than
# trusting the caller also keeps the BASE extraction below (which looks for "...")
# from swallowing the whole range.
case "$EXPLICIT_RANGE" in
  "") ;;
  *...*) ;;
  *..*) EXPLICIT_RANGE="${EXPLICIT_RANGE%%..*}...${EXPLICIT_RANGE#*..}" ;;
esac

# Every malformed form below fails SILENTLY without this block — git exits 0 and prints
# plausible output:
#   "feature" / a bare SHA  → git diff compares that ref against the WORKING TREE
#   "..X"                   → empty left side; git substitutes HEAD, re-injecting the
#                             local checkout this mode exists to keep out
#   "HEAD...X"              → BASE=HEAD makes the convention baseline the branch under review
#   an unfetched ref        → git diff exits 128 with EMPTY stdout, which reads as
#                             "no changed files"
if [ -n "$EXPLICIT_RANGE" ]; then
  case "$EXPLICIT_RANGE" in
    *...*) ;;
    *) echo "ERROR: '$EXPLICIT_RANGE' is not an A..B range — refusing to guess"; echo "VERDICT: error"; exit 1 ;;
  esac
  LEFT="${EXPLICIT_RANGE%%...*}"
  RIGHT="${EXPLICIT_RANGE#*...}"
  if [ -z "$LEFT" ] || [ -z "$RIGHT" ]; then
    echo "ERROR: range '$EXPLICIT_RANGE' has an empty side"; echo "VERDICT: error"; exit 1
  fi
  # ^{commit}, not a bare --verify: --verify only asks "does this resolve to an OBJECT",
  # so main^{tree} and main:some/file both pass it and then fail inside git diff ("is a
  # tree, not a commit") with EMPTY stdout — the silent shape above.
  # Two different causes, two different remedies. An object that exists but is not a commit
  # (a tree-ish, a blob path) is already local, so "fetch it first" sends the reader to do
  # something that changes nothing and produces the identical message on the retry.
  for ref in "$LEFT" "$RIGHT"; do
    if ! git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1; then
      if git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
        echo "ERROR: '$ref' resolves to an object but not a commit (a tree-ish or a path) — a range needs two commits"
      else
        echo "ERROR: '$ref' does not resolve to anything in $REPO — fetch it first"
      fi
      echo "VERDICT: error"; exit 1
    fi
  done
  # Reject the SPELLINGS that mean "whatever is checked out". Do NOT reject on SHA
  # equality with HEAD: a fresh clone sits on the default branch, so reviewing
  # origin/<default>...origin/<head> has LEFT == HEAD by construction — the primary
  # remote-PR flow.
  case "$LEFT" in
    HEAD|HEAD[~^]*|@|@[~^]*)
      echo "ERROR: left side '$LEFT' names the current checkout, not a stable baseline — pass the base branch (e.g. origin/develop)"
      echo "VERDICT: error"; exit 1 ;;
  esac
  if [ "$(git rev-parse "${LEFT}^{commit}")" = "$(git rev-parse "HEAD^{commit}")" ]; then
    echo "NOTE: left side '$LEFT' is the currently checked-out commit — expected right after a clone. If you meant to review the checked-out branch, the sides are swapped."
  fi
fi

CURRENT_BRANCH="$(git branch --show-current)"
echo "Current branch: ${CURRENT_BRANCH:-(detached)}"

# Base branch: an explicit range names it on the left side. Otherwise develop, main,
# then the remote HEAD branch. origin/<name> wins over the local branch: worktrees are cut
# from origin/develop while the main clone's local develop is rarely pulled, and a stale
# local base moves the merge-base back, so teammates' merged commits show up as this
# branch's changes (and Step 4's fixer would edit them).
if [ -n "$EXPLICIT_RANGE" ]; then
  BASE="${EXPLICIT_RANGE%%...*}"
elif git rev-parse --verify -q refs/remotes/origin/develop >/dev/null; then
  BASE="origin/develop"
elif git rev-parse --verify -q refs/heads/develop >/dev/null; then
  BASE="develop"
elif git rev-parse --verify -q refs/remotes/origin/main >/dev/null; then
  BASE="origin/main"
elif git rev-parse --verify -q refs/heads/main >/dev/null; then
  BASE="main"
else
  # `git remote show origin` needs the network and fails outright with no origin at all,
  # so this is the one BASE source that can come back empty.
  BASE="$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')"
fi

# An empty BASE is the silent shape the validation block above catches only for an
# explicit range. RANGE would become "...HEAD", and git reads an empty left side as HEAD:
# `git diff --name-only "...HEAD"` exits 0 with EMPTY output, so the verdict below would
# read "genuinely nothing in range" on a branch with unreviewed commits. Measured in a repo
# whose default branch is `trunk` with no reachable origin: 2 commits, verdict no-changes.
if [ -z "$BASE" ]; then
  echo "ERROR: could not determine a base branch — no origin/develop, develop, origin/main or main, and 'git remote show origin' gave nothing (no origin, or offline)."
  echo "       Pass the base explicitly: --range <base>..<head>"
  echo "VERDICT: error"
  exit 1
fi

# --- Incremental detection -----------------------------------------------------
REVIEW_MODE="full"
LAST_REVIEWED=""
if [ "$FORCE_FULL" != "true" ] && [ -z "$EXPLICIT_RANGE" ]; then
  PR_NUM="$(gh pr view --json number --jq '.number' 2>/dev/null || true)"
  PR_AUTHOR="$(gh pr view --json author --jq '.author.login' 2>/dev/null || true)"
  if [ -n "$PR_NUM" ]; then
    GH_USER="$(gh api user --jq .login 2>/dev/null || true)"
    OWNER_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
    if [ -n "$GH_USER" ] && [ -n "$OWNER_REPO" ]; then
      if [ "$GH_USER" != "$PR_AUTHOR" ]; then
        # Reviewing someone else's PR → your own last review commit
        LAST_REVIEWED="$(gh api "repos/$OWNER_REPO/pulls/$PR_NUM/reviews" \
          --jq "[.[] | select(.user.login==\"$GH_USER\")] | last | .commit_id" 2>/dev/null || true)"
      else
        # Your own PR → the latest review from others
        LAST_REVIEWED="$(gh api "repos/$OWNER_REPO/pulls/$PR_NUM/reviews" \
          --jq "[.[] | select(.user.login!=\"$GH_USER\")] | last | .commit_id" 2>/dev/null || true)"
      fi
      if [ -n "$LAST_REVIEWED" ] && [ "$LAST_REVIEWED" != "null" ] && \
         git merge-base --is-ancestor "$LAST_REVIEWED" HEAD 2>/dev/null && \
         [ "$LAST_REVIEWED" != "$(git rev-parse HEAD)" ]; then
        REVIEW_MODE="incremental"
      fi
    fi
  fi
fi

if [ -n "$EXPLICIT_RANGE" ]; then
  RANGE="$EXPLICIT_RANGE"
  REVIEW_MODE="explicit"
  echo "Mode: explicit range (user-supplied)"
elif [ "$REVIEW_MODE" = "incremental" ]; then
  RANGE="$LAST_REVIEWED...HEAD"
  echo "Mode: incremental (since last review at $(printf '%.7s' "$LAST_REVIEWED"))"
else
  RANGE="$BASE...HEAD"
  echo "Mode: full"
fi
echo "Base: $BASE"
case "$BASE" in
  origin/*)
    LOCAL_NAME="${BASE#origin/}"
    if git rev-parse --verify -q "refs/heads/$LOCAL_NAME" >/dev/null && \
       [ "$(git rev-parse "refs/heads/$LOCAL_NAME")" != "$(git rev-parse "$BASE")" ]; then
      echo "NOTE: local $LOCAL_NAME differs from $BASE — using $BASE (not fetched in this run; fetch first if it may be stale)"
    fi
    ;;
esac
echo "Diff range: $RANGE"

# --- Changed files -------------------------------------------------------------
# Passed on UNFILTERED. Generated and lock files are excluded by the Step 2 subagent,
# which is the only place the coding-standards exclusion patterns get loaded.
echo ""
echo "=== Changed files ==="
# One call, captured, with stderr kept apart: a bad ref exits 128 with EMPTY stdout and
# its fatal on stderr, so folding them together would print the error where a filename
# belongs and count it as a changed file.
DIFF_ERR="$(mktemp)"
CHANGED="$(git diff --name-only "$RANGE" 2>"$DIFF_ERR")"
DIFF_RC=$?
[ -n "$CHANGED" ] && printf '%s\n' "$CHANGED"
CHANGED_COUNT="$(printf '%s' "$CHANGED" | grep -c . || true)"
echo "(git diff exit=$DIFF_RC)"
[ -s "$DIFF_ERR" ] && sed 's/^/  stderr: /' "$DIFF_ERR"
rm -f "$DIFF_ERR"

echo ""
echo "=== Working tree ==="
# Exit code, not emptiness: a bare git run outside a repo exits non-zero and prints
# nothing, and an emptiness test reads that silence as "clean".
WT="$(git status --porcelain 2>/dev/null)"
WT_RC=$?
if [ "$WT_RC" -ne 0 ]; then
  echo "ERROR: git status failed (exit=$WT_RC) — not a clean tree, an unknown one"
elif [ -z "$WT" ]; then
  echo "clean"
else
  echo "$(printf '%s\n' "$WT" | grep -c .) uncommitted file(s) — NOT part of a three-dot range:"
  printf '%s\n' "$WT" | sed 's/^/  /'
fi

echo ""
echo "=== Commits in range ==="
# TWO dots for the log, three for the diff: `git log A...B` is the symmetric difference,
# so it also lists base-side commits, and the commit-quality check would then judge
# base-branch commits as if they belonged to the branch under review.
git log --oneline "${RANGE%%...*}..${RANGE#*...}"

echo ""
echo "=== Base-branch commits (convention baseline) ==="
git log --oneline -10 "$BASE"

echo ""
if [ "$DIFF_RC" -ne 0 ]; then
  echo "VERDICT: range-unresolved — the range failed to resolve; stop and say so"
  exit 2
elif [ "$CHANGED_COUNT" -eq 0 ]; then
  echo "VERDICT: no-changes — genuinely nothing in range; inform the user and stop"
  exit 3
fi
echo "VERDICT: ok — $CHANGED_COUNT changed file(s), mode=$REVIEW_MODE"
exit 0
