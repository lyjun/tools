#!/usr/bin/env bash
# pr-head-tree.sh — run a command against a PR's head tree without checking it out.
#
# Two callers: this skill's coverage gate (a Go build at the head) and the multi-PR review
# flow's Step 2 (`helm unittest` on a chart subdirectory). The second one reaches it by
# absolute path, so moving or renaming this file means grepping ~/.claude/skills for it.
#
# Replaces two prose recipes that had already drifted apart: one archived the repo root
# because `go build ./...` needs go.mod at the top, the other archived a chart subdirectory
# because that is what `helm unittest` takes, and each stated its own choice as the rule.
# The tool root is a parameter, which is what makes both correct at once.
#
# The ref is always the pull ref. `fetch origin <headRefName>` fails for a fork PR (the head
# is not a branch on the base remote) AND for any merged PR whose branch was deleted on
# merge — the local convention. `pull/<num>/head` exists in all three cases; measured on a
# merged PR whose branch was gone, the branch fetch failed and the pull ref fetched clean.
#
# Usage:
#   pr-head-tree.sh --repo PATH --pr N [--subpath P] -- <command...>
#
#   --subpath P   the tool root: the command runs in <tree>/P instead of <tree>.
#                 Omit it for a Go build (go.mod must be at the top); pass the chart's
#                 own directory for helm unittest.
#   -h | --help   print this block
#
# Both things this script creates are removed on exit, including on failure or interrupt:
# the extracted tree, and the `pr-N` branch ref IF this run is what fetched it. A `pr-N`
# that already existed is left alone — x-pr-review creates one deliberately for a fork PR
# and reads the head at it, so deleting that would pull the ref out from under a review in
# progress.
#
# Exit: the command's own exit code · 1 usage/setup error

set -u

# bash 3.2 — which is what /usr/bin/env bash resolves to on this machine — returns 1 from
# `shift 2` when only one argument remains AND DOES NOT SHIFT, silently. With no `set -e` the
# loop below then re-tests the same $1 forever: no output, no exit code, no VERDICT line, just
# a spin until something kills it. That is the one failure here a caller cannot name, because
# every contract downstream says to read the VERDICT line. Guard before shifting.
usage_and_exit() {
  # Bounded on the comment block itself, not on hard-coded line numbers: the previous
  # `sed -n '2,20p'` form printed whatever happened to sit at those lines, which after a
  # comment edit was `set -u` and the variable initialisers — source code in a help screen.
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
  exit 0
}

need() { [ "$1" -ge 2 ] || { echo "ERROR: $2 needs a value"; echo "VERDICT: error"; exit 1; }; }

REPO=""; NUM=""; SUBPATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    need $# --repo; REPO="$2"; shift 2 ;;
    --pr)      need $# --pr; NUM="$2"; shift 2 ;;
    --subpath) need $# --subpath; SUBPATH="$2"; shift 2 ;;
    --)        shift; break ;;
    -h|--help) usage_and_exit ;;
    # A non-flag argument here is almost never a misspelled flag — it is the command,
    # passed without the mandatory `--`. Saying "unknown argument 'ls'" sends the reader
    # hunting for a typo in a flag name that is not there.
    -*) echo "ERROR: unknown flag '$1'"; echo "VERDICT: error"; exit 1 ;;
    *)  echo "ERROR: '$1' is not a flag — the command must come after '--'"
        echo "usage: pr-head-tree.sh --repo PATH --pr N [--subpath P] -- <command...>"
        echo "VERDICT: error"; exit 1 ;;
  esac
done

if [ -z "$REPO" ] || [ -z "$NUM" ] || [ $# -eq 0 ]; then
  echo "usage: pr-head-tree.sh --repo PATH --pr N [--subpath P] -- <command...>"
  echo "VERDICT: error"; exit 1
fi
# Absolutise the repo argument here, before anything reads it. Everything below that
# compares a path we built against a path git returned needs both sides in the same form:
# `git rev-parse --show-toplevel` always answers absolute, so a relative --repo made the
# submodule check below compare "/abs/path" against "./rel/path" and report every
# populated submodule as missing.
REPO="$(cd "$REPO" 2>/dev/null && pwd -P)" || true
if [ -z "$REPO" ]; then
  echo "ERROR: cannot enter the --repo path"; echo "VERDICT: error"; exit 1
fi
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "ERROR: '$REPO' is not a git repo"; echo "VERDICT: error"; exit 1; }

# Note whether pr-N already exists, so the cleanup below only removes a ref this run made.
PREEXISTING_REF="no"
git -C "$REPO" rev-parse --verify --quiet "refs/heads/pr-$NUM" >/dev/null 2>&1 && PREEXISTING_REF="yes"

# --force: the ref may already exist from an earlier round, and the PR may have been
# force-pushed since.
if ! git -C "$REPO" fetch origin "pull/$NUM/head:pr-$NUM" --force --quiet 2>&1; then
  echo "ERROR: could not fetch pull/$NUM/head — check the PR number and remote access"
  echo "VERDICT: error"; exit 1
fi
SHA="$(git -C "$REPO" rev-parse --short "pr-$NUM")"

# The tree gets its own subdirectory so nothing this script needs — tar files, the
# missing-submodule marker — lands inside the tree the command then runs in. A repo with a
# test that walks its own tree (arx-platform-api has one) would otherwise see the scratch
# files as repo content.
WORK="$(mktemp -d)"
TMP="$WORK/tree"
mkdir -p "$TMP"
cleanup() {
  rm -rf "$WORK"
  [ "$PREEXISTING_REF" = "no" ] && git -C "$REPO" branch -D "pr-$NUM" >/dev/null 2>&1
  return 0
}
trap cleanup EXIT INT TERM

# Archive to a file, then extract. `git archive ... | tar -x` cannot report the archive's
# failure: the pipeline's exit code is tar's, and tar succeeds on empty input — so a
# subpath that does not exist at this ref would leave an empty tree and the error would
# only surface later as a cd failure, blamed on the command instead of the path.
if [ -n "$SUBPATH" ]; then
  if [ -z "$(git -C "$REPO" ls-tree -d --name-only "pr-$NUM" -- "$SUBPATH" 2>/dev/null)" ]; then
    echo "ERROR: '$SUBPATH' is not a directory at pr-$NUM ($SHA)"
    echo "VERDICT: error"; exit 1
  fi
  git -C "$REPO" archive -o "$WORK/tree.tar" "pr-$NUM" "$SUBPATH" || {
    echo "ERROR: archive of $SUBPATH at pr-$NUM failed"; echo "VERDICT: error"; exit 1; }
  ROOT="$TMP/$SUBPATH"
else
  git -C "$REPO" archive -o "$WORK/tree.tar" "pr-$NUM" || {
    echo "ERROR: archive of pr-$NUM failed"; echo "VERDICT: error"; exit 1; }
  ROOT="$TMP"
fi
tar -x -f "$WORK/tree.tar" -C "$TMP" || {
  echo "ERROR: extracting the archive failed"; echo "VERDICT: error"; exit 1; }
rm -f "$WORK/tree.tar"
[ -d "$ROOT" ] || { echo "ERROR: '$ROOT' is not a directory after extraction"; echo "VERDICT: error"; exit 1; }

# git archive writes a submodule as an EMPTY directory, so anything reading through one
# breaks in a way that names the wrong file: arx-platform-api's `//go:embed
# all:arx-welcome-wizard/template` fails with "no matching files found" in embed.go, and
# because a handler package imports it, narrowing the build to the PR's own packages does
# not avoid it either. Populate each one from the local clone at the commit the ref records.
# One level only — a submodule inside a submodule is not followed.
# The failure count goes to a FILE, not a variable: this loop is the right-hand side of a
# pipeline, so it runs in a subshell and any variable it sets is gone by the time the
# verdict is written — which would leave the verdict silently claiming a complete tree.
# Split on TAB for the path: ls-tree's format is "<mode> <type> <object>\t<path>", so
# splitting the whole line on whitespace truncates any path containing a space.
: > "$WORK/.submodules_missing"
git -C "$REPO" ls-tree -r "pr-$NUM" 2>/dev/null |
  awk -F'\t' '{split($1, meta, " "); if (meta[2] == "commit") print meta[3] "\t" $2}' |
while IFS="$(printf '\t')" read -r sub_sha sub_path; do
  # A --subpath extraction only contains that subtree, so submodules outside it have no
  # directory here and this check is what skips them.
  [ -d "$TMP/$sub_path" ] || continue
  # An uninitialised submodule is an EMPTY directory, and `git -C` there walks up and finds
  # the PARENT repo — so a bare cat-file would be answered by the wrong repository. Require
  # the toplevel to be the submodule itself before trusting anything it says.
  sub_top="$(git -C "$REPO/$sub_path" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ "$sub_top" = "$REPO/$sub_path" ] && git -C "$REPO/$sub_path" cat-file -e "${sub_sha}^{commit}" 2>/dev/null &&
     git -C "$REPO/$sub_path" archive -o "$WORK/sub.tar" "$sub_sha" 2>/dev/null &&
     tar -x -f "$WORK/sub.tar" -C "$TMP/$sub_path"; then
    echo "SUBMODULE: $sub_path @ $(printf '%.7s' "$sub_sha")"
  else
    echo "SUBMODULE: $sub_path @ $(printf '%.7s' "$sub_sha") — NOT POPULATED (not in the local clone at that commit); anything reading through it will fail"
    echo "$sub_path" >> "$WORK/.submodules_missing"
  fi
  rm -f "$WORK/sub.tar"
done
MISSING_SUBS="$(grep -c . "$WORK/.submodules_missing" 2>/dev/null || true)"
[ -n "$MISSING_SUBS" ] || MISSING_SUBS=0

echo "REF: pr-$NUM ($SHA) — fetched from pull/$NUM/head"
echo "TREE: $ROOT"
# %q so the line round-trips: `$*` flattens argv and drops quoting, turning
# `sh -c 'pwd; ls'` into a line that runs `sh -c pwd` and then `ls` in the reader's own
# shell. This is the only record of what executed, inside the evidence block a pass cites.
printf 'RAN:'; printf ' %q' "$@"; printf '\n'
echo "--- command output ---"
( cd "$ROOT" && "$@" )
RC=$?
echo "--- end command output ---"
echo "EXIT: $RC"
# The incompleteness belongs ON the verdict line, not only on the SUBMODULE lines above.
# The verdict is what a pre-flight gate cites as its evidence, so a bare "ok" over a tree
# missing a submodule is the false-clean shape this script exists to prevent — the command
# can exit 0 simply by not reading through the empty directory.
if [ "$MISSING_SUBS" -gt 0 ]; then
  INCOMPLETE=" — TREE INCOMPLETE: $MISSING_SUBS submodule(s) not populated, so this run did not exercise anything reading through them"
else
  INCOMPLETE=""
fi
if [ "$RC" -eq 0 ]; then
  echo "VERDICT: ok — ran at pr-$NUM ($SHA), NOT at whatever branch $REPO is checked out on$INCOMPLETE"
else
  echo "VERDICT: failed — exit $RC at pr-$NUM ($SHA)$INCOMPLETE"
fi
exit "$RC"
