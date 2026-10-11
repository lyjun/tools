#!/usr/bin/env bash
# pr-size.sh — split a diff into hand-written and generated, so review depth is calibrated
# on the lines a person typed.
#
# A PR's own `additions + deletions` counts generator output, which lets `buf generate`'s
# volume decide how closely a human reads. Measured on one real PR: 543 raw versus 166
# hand-written — two different tiers, and the tier gates three downstream decisions. (165 was
# the hand-tally of that same PR, and it was wrong by one deletion — which is this script's
# other reason for existing.)
#
# This prints numbers only. The tier boundaries live in x-pr-review's calibration section and
# nowhere else — every site that acts on the tier names it rather than restating the numbers,
# and a copy here would be the one restatement that can silently disagree with all of them.
#
# The exclusion patterns are NOT copied here either — they are read at runtime from
# x-coding-standards' own SKILL.md, which states it is the single source. Both of its tests
# apply, and the content test cannot be replaced by filenames: in this workspace 6 of 56
# files named models.go / db.go are hand-written, so a filename shortcut would drop
# hand-written code out of the count and under-state the depth needed.
#
# Usage:
#   pr-size.sh --repo PATH --range A..B
#   pr-size.sh -h | --help
#
# Takes the same ref pair the review is reading at, so the number describes the code under
# review rather than GitHub's view of the PR.
#
# One deliberate over-count: rename detection is OFF (see --no-renames below), so a renamed
# file counts as a full delete plus a full add rather than its actual delta. Measured on a
# 40-commit window of arx-platform-core with one rename in it: 33639 lines with detection,
# 34189 without — one renamed ~355-line test file accounting for the whole +550.
# The price is paid to keep the path column a real path both tests can read; when a PR reads
# large and its diff is mostly renames, check whether the delta says the same thing.
#
# Exit: 0 ok, `-h`, or `no-changes` — a valid range that is genuinely empty; this measures,
#         it does not gate, so an empty range is not an error here
#       1 usage error (unknown/missing/empty flag value, an unenterable or non-git --repo),
#         a malformed range, a range side that is not a commit, or a failed git diff
#       3 the exclusion list could not be read, or no longer behaves like one
# Nothing returns 2. Every path prints a VERDICT line before exiting.

set -u

# ${HOME:-} rather than $HOME: with `set -u` and HOME unset, a bare $HOME aborts the script
# on this line — the one exit that would print no VERDICT line at all, which every caller's
# contract says to read.
if [ -z "${HOME:-}" ]; then
  echo "ERROR: HOME is unset, so the exclusion list's path cannot be built"
  echo "VERDICT: error"; exit 1
fi
STD="$HOME/.claude/skills/x-coding-standards/SKILL.md"

usage_and_exit() {
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
  exit 0
}

# bash 3.2 — what /usr/bin/env bash resolves to here — returns 1 from `shift 2` with one
# argument left and DOES NOT SHIFT, silently, so the loop would spin forever with no output.
# An empty value is checked here too, so the message names the flag rather than falling through
# to the generic usage line — the sibling range-detect.sh words it identically.
need() {
  [ "$1" -ge 2 ] || { echo "ERROR: $2 needs a value"; echo "VERDICT: error"; exit 1; }
  [ -n "$3" ] || { echo "ERROR: $2 was given an empty value"; echo "VERDICT: error"; exit 1; }
}

REPO=""; RANGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)  need $# --repo "${2:-}"; REPO="$2"; shift 2 ;;
    --range) need $# --range "${2:-}"; RANGE="$2"; shift 2 ;;
    -h|--help) usage_and_exit ;;
    *) echo "ERROR: unknown argument '$1'"; echo "VERDICT: error"; exit 1 ;;
  esac
done

if [ -z "$REPO" ] || [ -z "$RANGE" ]; then
  echo "usage: pr-size.sh --repo PATH --range A..B"
  echo "VERDICT: error"; exit 1
fi
REPO="$(cd "$REPO" 2>/dev/null && pwd -P)" || true
[ -n "$REPO" ] || { echo "ERROR: cannot enter the --repo path"; echo "VERDICT: error"; exit 1; }
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "ERROR: '$REPO' is not a git repo"; echo "VERDICT: error"; exit 1; }

case "$RANGE" in
  *...*) ;;
  *..*) RANGE="${RANGE%%..*}...${RANGE#*..}" ;;
  *) echo "ERROR: '$RANGE' is not an A..B range"; echo "VERDICT: error"; exit 1 ;;
esac
LEFT="${RANGE%%...*}"
RIGHT="${RANGE#*...}"
if [ -z "$LEFT" ] || [ -z "$RIGHT" ]; then
  echo "ERROR: range '$RANGE' has an empty side"; echo "VERDICT: error"; exit 1
fi
# BOTH sides, not just the right one. A range whose left side does not resolve makes
# `git diff --numstat` exit 128 with EMPTY stdout, and the counting loop below then reports
# `VERDICT: no-changes` at exit 0 — a size of zero reads as "nothing to review" and
# calibrates the whole review down. The sibling range-detect.sh rejects the same input with
# `VERDICT: error`; this validating both sides is what makes the two agree.
# ^{commit} rather than a bare --verify, and the two causes get different remedies: an
# object that is not a commit (main^{tree}, a path) is already local, so "fetch it first"
# would send the reader to do something that changes nothing.
for ref in "$LEFT" "$RIGHT"; do
  if ! git -C "$REPO" rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1; then
    if git -C "$REPO" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
      echo "ERROR: '$ref' resolves to an object but not a commit (a tree-ish or a path) — a range needs two commits"
    else
      echo "ERROR: '$ref' does not resolve to anything in $REPO — fetch it first"
    fi
    echo "VERDICT: error"; exit 1
  fi
done

# Reject the SPELLINGS that mean "whatever is checked out", the same set range-detect.sh
# rejects. `HEAD...<head>` resolves fine, so nothing above catches it, and the number it
# then produces is a function of whatever the clone happens to sit on: measured on
# arx-platform-api, whose local develop was stale against origin/develop, `HEAD...pr-864`
# gave 496 hand-written lines against a true 30 — 16× off, and across the `> 300` boundary
# into the large tier. When HEAD happens to equal the right side it collapses further, to
# `no-changes` at exit 0.
# Not a SHA comparison against HEAD: a fresh clone sits on the default branch, so
# origin/<default>...origin/<head> has LEFT == HEAD by construction — the normal remote-PR
# shape, which must keep working.
case "$LEFT" in
  HEAD|HEAD[~^]*|@|@[~^]*)
    echo "ERROR: left side '$LEFT' names the current checkout, not a stable baseline — pass the base branch (e.g. origin/develop)"
    echo "VERDICT: error"; exit 1 ;;
esac

# --- Test 2: the filename ERE, read from its single source ----------------------
# Extracted rather than copied. If the extraction fails the filter would be empty and
# every generated file would count as hand-written — silently over-stating the size, which
# is why this exits instead of continuing.
# The fence match is prefix-only (`/^```/`, not `/^```$/`): adding a language tag to that
# fence in the source document is a one-token markdown edit that would otherwise make this
# match nothing and take the tool out of service.
ERE="$(awk '
  /Generated & Lock File Exclusions/ {insec=1}
  insec && /^```/ {fence++; next}
  insec && fence==1 && !done {print; done=1}
' "$STD" 2>/dev/null | head -1)"
if [ -z "$ERE" ]; then
  echo "ERROR: could not read the exclusion pattern from $STD"
  echo "       Without it every generated file counts as hand-written and the size is overstated."
  echo "VERDICT: unavailable"; exit 3
fi

# Emptiness is not the only way the extraction goes wrong. If that SKILL.md is restructured
# and the awk lands on a DIFFERENT fenced line, the result is still a non-empty pattern — and
# an over-broad one classifies hand-written files as generated, printing a near-zero
# hand-written figure under `VERDICT: ok`. That under-calibrates the whole review, and nothing
# in the output says why.
#
# One negative probe is not enough, and the first version of this block had exactly one. The
# pattern has 16 arms; a plausible over-broad edit (`docs/` instead of `docs/swagger/`,
# `^api/`, `^internal/database/`) misses whichever single subtree the probe happens to sample.
# Measured: collapsing `docs/swagger/` to `docs/` still passed a lone
# `internal/handler/v1/…` probe while turning api#864's 30 hand-written lines into 24.
# So the negative set is taken from the files x-coding-standards itself names as the
# hand-written ones its exclusion list must never swallow.
CANARY_BAD=""

# Validity first, and once. An unusable pattern makes every probe below fail for the same
# single reason, so probing first would print one cause eight times and bury it.
printf 'x\n' | grep -qE "$ERE" 2>/dev/null
if [ "$?" -gt 1 ]; then
  echo "ERROR: grep cannot use the pattern read from $STD — it is not a valid ERE"
  echo "       extracted: $ERE"
  echo "       (grep's own complaint is on stderr above.)"
  echo "VERDICT: unavailable"; exit 3
fi

probe() { # probe <path> <yes|no — must it be excluded?>
  # grep as a guard has THREE outcomes, not two: match (0), no match (1), and REJECTED THE
  # PATTERN (2, an invalid ERE). Folding 2 into the no-match branch is what made the earlier
  # version report a syntactically broken pattern as "too narrow" — a true statement about
  # the symptom pointing at the wrong cause, which sends the reader to edit the arm list.
  printf '%s\n' "$1" | grep -qE "$ERE" 2>/dev/null
  rc=$?
  case "$rc:$2" in
    0:yes|1:no) ;;
    1:yes) CANARY_BAD="$CANARY_BAD
       - a generated name ($1) is NOT matched" ;;
    0:no)  CANARY_BAD="$CANARY_BAD
       - a hand-written name ($1) IS matched" ;;
    *)     CANARY_BAD="$CANARY_BAD
       - grep rejects this pattern outright (exit $rc): it is not a valid ERE" ;;
  esac
}
probe 'api/foo/v1/bar.pb.go'                   yes
probe 'go.sum'                                 yes
probe 'docs/swagger/public_swagger.yaml'       yes
probe 'api/http/v1/models.go'                  no
probe 'internal/handler/v1/marketplace.go'     no
probe 'internal/database/models.go'            no
probe 'internal/auth/db.go'                    no
probe 'docs/public-api.md'                     no
if [ -n "$CANARY_BAD" ]; then
  echo "ERROR: the pattern read from $STD no longer behaves like the exclusion list:$CANARY_BAD"
  echo "       extracted: $ERE"
  echo "       Refusing to count — the split would be wrong in a direction the output cannot show."
  echo "VERDICT: unavailable"; exit 3
fi

echo "repo: $REPO"
echo "range: $RANGE"
# The pattern itself, not just its provenance. A wrong pattern that happens to pass the probes
# above would otherwise leave no trace in the output for a reader to check against.
echo "exclusions: read from x-coding-standards/SKILL.md (single source)"
echo "  pattern: $ERE"
echo ""

HW_L=0; HW_F=0; GEN_L=0; GEN_F=0
GEN_LIST=""
HW_LIST=""

# Captured with its exit code BEFORE the loop reads it. Command substitution inside the
# loop's heredoc discards that code — every git failure would arrive as empty input and
# leave the loop reporting a size of zero. stderr is kept apart so a fatal cannot be
# mistaken for a numstat row.
#
# Two flags exist to keep the path column a plain path, because both tests below are applied
# to that column verbatim:
#   --no-renames — a detected rename is emitted as `old => new` or `dir/{old => new}`, and
#     that whole string is what gets matched. An unanchored arm then fires on the SOURCE path
#     (`docs/proto/a.md => internal/b.md` counted as generated, hiding hand-written lines),
#     while the brace form's trailing `}` breaks every `$`-anchored arm the other way and
#     also makes `git show "$RIGHT:<that string>"` fail, so the marker test misses too.
#     Without rename detection the same change arrives as one delete plus one add, each with
#     a real path that both tests can read.
#   core.quotePath=false — by default git renders a non-ASCII path as
#     `"internal/h\303\251llo.pb.go"`, quotes included; the trailing quote breaks the ERE and
#     the quoted string is not a path `git show` can resolve, so a generated file counted as
#     hand-written. (A tab or a literal quote in a name is still escaped and still misses,
#     but that direction over-states the size, which is the safe one.)
NUMSTAT_ERR="$(mktemp)"
NUMSTAT="$(git -C "$REPO" -c core.quotePath=false diff --numstat --no-renames "$RANGE" 2>"$NUMSTAT_ERR")"
NUMSTAT_RC=$?
if [ "$NUMSTAT_RC" -ne 0 ]; then
  echo "ERROR: git diff --numstat '$RANGE' failed (exit=$NUMSTAT_RC)"
  [ -s "$NUMSTAT_ERR" ] && sed 's/^/  stderr: /' "$NUMSTAT_ERR"
  rm -f "$NUMSTAT_ERR"
  echo "VERDICT: error"; exit 1
fi
rm -f "$NUMSTAT_ERR"

# Binary files come back as "-\t-\tpath": count the file, no lines.
while IFS="$(printf '\t')" read -r add del path; do
  [ -n "${path:-}" ] || continue
  case "$add" in -) add=0 ;; esac
  case "$del" in -) del=0 ;; esac
  lines=$((add + del))
  reason=""
  if printf '%s\n' "$path" | grep -qE "$ERE"; then
    reason="filename"
  else
    case "$path" in
      *.go)
        # Test 1, the primary one for Go: the marker must be in the first three lines.
        # `git grep` cannot bound a line range, so a whole-file grep would also match a
        # hand-written file that merely mentions the marker further down.
        #
        # Read from whichever side HAS the file. A file deleted in the range does not exist at
        # $RIGHT, so `git show` exits 128 — and that code is discarded twice (by 2>/dev/null
        # and by the pipe into head), leaving `reason` empty. A deleted generated file whose
        # name matches no filename arm then counted as hand-written deletions; measured on a
        # scratch repo with `internal/zz_deepcopy.go` carrying the protoc marker on line 1.
        SIDE="$RIGHT"
        git -C "$REPO" cat-file -e "$RIGHT:$path" 2>/dev/null || SIDE="$LEFT"
        if git -C "$REPO" cat-file -e "$SIDE:$path" 2>/dev/null &&
           git -C "$REPO" show "$SIDE:$path" 2>/dev/null | head -3 |
             grep -qE 'Code generated by .* DO NOT EDIT\.'; then
          reason="marker"
        fi
        ;;
    esac
  fi
  if [ -n "$reason" ]; then
    GEN_L=$((GEN_L + lines)); GEN_F=$((GEN_F + 1))
    GEN_LIST="$GEN_LIST
  $(printf '%6s' "$lines")  $path  ($reason)"
  else
    HW_L=$((HW_L + lines)); HW_F=$((HW_F + 1))
    HW_LIST="$HW_LIST
  $(printf '%6s' "$lines")  $path"
  fi
done <<EOF
$NUMSTAT
EOF

echo "=== hand-written ($HW_F files, $HW_L lines) ==="
[ -n "$HW_LIST" ] && printf '%s\n' "${HW_LIST#
}"
echo ""
echo "=== generated / lock, excluded ($GEN_F files, $GEN_L lines) ==="
if [ -n "$GEN_LIST" ]; then
  printf '%s\n' "${GEN_LIST#
}"
else
  echo "  (none)"
fi
echo ""
echo "hand-written: $HW_L lines / $HW_F files"
echo "generated:    $GEN_L lines / $GEN_F files"
if [ "$((HW_F + GEN_F))" -eq 0 ]; then
  # Two very different situations print byte-identically here: a PR that genuinely changes
  # nothing, and a range whose sides are the wrong way round. `pr-864...origin/develop` diffs
  # the merge base against origin/develop, which really is empty — git is not failing, so
  # there is no error to catch, and asserting "the range is empty" states the benign reading
  # of the two. Checking the other direction separates them for the price of one diff.
  REV="$(git -C "$REPO" -c core.quotePath=false diff --numstat --no-renames "$RIGHT...$LEFT" 2>/dev/null | grep -c . || true)"
  if [ "${REV:-0}" -gt 0 ]; then
    echo "VERDICT: no-changes — nothing in '$RANGE', but '$RIGHT...$LEFT' has $REV changed file(s): the sides are probably swapped"
    exit 0
  fi
  echo "VERDICT: no-changes — the range is empty in both directions"
  exit 0
fi
echo "VERDICT: ok — calibrate on the hand-written figure; the tier boundaries are in x-pr-review's calibration section, not here"
exit 0
