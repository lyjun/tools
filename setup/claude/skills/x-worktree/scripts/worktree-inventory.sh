#!/usr/bin/env bash
#
# Lists every git worktree registered under one issue folder, across every
# repository in the workspace. Read-only.
#
# Exists because the same listing is needed at two points in the workflow —
# before creating a worktree (does this repo already have one here? then this
# is a second slice of the same spec) and before cleaning one up (which
# directories and branches actually belong to this issue?) — and both call
# sites otherwise carried an inline command with two placeholders to fill and
# one repetition to remember. The repetition is the half people miss:
# `git worktree list` answers per main clone, so an issue folder holding two
# repositories' worktrees shows only half of itself when asked inside one of
# them. This script asks every repository in the workspace, so the coverage is
# its behaviour rather than the reader's diligence.
#
# Output: one WORKTREE: line per hit, the values it actually read, then a
# VERDICT: line. Exit 0 = ok, 1 = error (usage/input), 3 = unavailable (ran,
# but could not read something it needed). Read the VERDICT line, not the
# shell's status — several commands run mid-script.

set -uo pipefail

usage() {
	cat <<'EOF'
Usage: worktree-inventory.sh --issue-slug <slug> [--workspace <path>]

  --issue-slug   the issue folder's name under <workspace>/worktree/.
                 One path segment, e.g. issue-112-raid1-system-disk
  --workspace    the workspace root holding the main clones and worktree/.
                 Defaults to the nearest ancestor of $PWD that contains a
                 "worktree" directory.
EOF
}

ISSUE_SLUG=""
WORKSPACE=""
# Tracked apart from the value: an empty --workspace must be an error, not a
# silent fall-through to the cwd search. Falling through would report ok for a
# workspace the caller never named.
WORKSPACE_GIVEN=0

while [ $# -gt 0 ]; do
	case "$1" in
	--issue-slug)
		# Guarded rather than relying on `shift 2`: with one argument left it
		# returns 1 and shifts nothing, so the loop spins with no output.
		if [ $# -lt 2 ]; then
			echo "VERDICT: error — --issue-slug given with no value"
			exit 1
		fi
		ISSUE_SLUG="$2"
		shift 2
		;;
	--workspace)
		if [ $# -lt 2 ]; then
			echo "VERDICT: error — --workspace given with no value"
			exit 1
		fi
		WORKSPACE="$2"
		WORKSPACE_GIVEN=1
		shift 2
		;;
	-h | --help)
		usage
		echo "VERDICT: ok — usage printed"
		exit 0
		;;
	*)
		usage >&2
		echo "VERDICT: error — unknown argument '$1'"
		exit 1
		;;
	esac
done

if [ -z "$ISSUE_SLUG" ]; then
	echo "VERDICT: error — --issue-slug is required and must not be empty"
	exit 1
fi

# A slug with a separator would silently widen the path prefix every hit is
# matched against, so reject it here rather than let it match nothing.
case "$ISSUE_SLUG" in
*/*)
	echo "VERDICT: error — --issue-slug must be one path segment, got '$ISSUE_SLUG'"
	exit 1
	;;
esac

if [ "$WORKSPACE_GIVEN" -eq 1 ] && [ -z "$WORKSPACE" ]; then
	echo "VERDICT: error — --workspace given but empty; omit the flag to search from \$PWD, or name a path"
	exit 1
fi

if [ -z "$WORKSPACE" ]; then
	dir=$(pwd -P)
	while [ "$dir" != "/" ]; do
		if [ -d "$dir/worktree" ]; then
			WORKSPACE="$dir"
			break
		fi
		dir=$(dirname "$dir")
	done
fi

if [ -z "$WORKSPACE" ]; then
	echo "VERDICT: error — no workspace found; pass --workspace, or run from inside one (an ancestor holding a worktree/ directory)"
	exit 1
fi
if [ ! -d "$WORKSPACE/worktree" ]; then
	echo "VERDICT: error — '$WORKSPACE' has no worktree/ directory"
	exit 1
fi

ISSUE_DIR="$WORKSPACE/worktree/$ISSUE_SLUG"
PREFIX="$ISSUE_DIR/"

echo "WORKSPACE: $WORKSPACE"
if [ -d "$ISSUE_DIR" ]; then
	echo "ISSUE_FOLDER: $ISSUE_DIR (exists)"
else
	# Printed so an empty result can be told apart from a mistyped slug: no
	# folder and no worktrees is a fresh issue, a folder with no worktrees is
	# one whose worktrees are already gone.
	echo "ISSUE_FOLDER: $ISSUE_DIR (missing on disk)"
fi

repos=()
for candidate in "$WORKSPACE"/*/; do
	[ -d "$candidate" ] || continue
	name=$(basename "$candidate")
	[ "$name" = "worktree" ] && continue
	[ -e "$candidate/.git" ] || continue
	repos+=("$name")
done

found=0
scanned=0
failed=0
repo=""
wt_path=""
wt_branch=""
wt_detached=0

emit() {
	[ -n "$wt_path" ] || return 0
	case "$wt_path" in
	"$PREFIX"*) ;;
	*) return 0 ;;
	esac
	found=$((found + 1))
	if [ "$wt_detached" -eq 1 ]; then
		echo "WORKTREE: $wt_path  repo=$repo  branch=(detached HEAD — nothing to delete)"
	else
		echo "WORKTREE: $wt_path  repo=$repo  branch=$wt_branch"
	fi
}

for repo in ${repos[@]+"${repos[@]}"}; do
	main="$WORKSPACE/$repo"
	scanned=$((scanned + 1))
	if ! out=$(git -C "$main" worktree list --porcelain 2>/dev/null); then
		echo "REPO_UNREADABLE: $repo — git worktree list failed"
		failed=$((failed + 1))
		continue
	fi

	wt_path=""
	wt_branch=""
	wt_detached=0
	# The trailing blank line makes the last record flush through the same
	# branch as every other one; porcelain's own terminator is not relied on.
	while IFS= read -r line; do
		case "$line" in
		"worktree "*)
			emit
			wt_path="${line#worktree }"
			wt_branch=""
			wt_detached=0
			;;
		"branch "*)
			wt_branch="${line#branch refs/heads/}"
			;;
		detached)
			wt_detached=1
			;;
		"")
			emit
			wt_path=""
			;;
		esac
	done <<EOF
$out

EOF
done

# The count is what makes "every repository was asked" checkable — compare it
# against the workspace's own repository count if it looks wrong. The names are
# left out because listing 30-odd of them on every call buries the WORKTREE
# lines; a repository that could not be read is named above instead, which is
# the case where the name carries information.
echo "REPOS_SCANNED: $scanned"
echo "WORKTREES_FOUND: $found"

if [ "$scanned" -eq 0 ]; then
	echo "VERDICT: unavailable — no git repositories directly under '$WORKSPACE'; nothing was searched"
	exit 3
fi
if [ "$failed" -gt 0 ]; then
	echo "VERDICT: unavailable — $failed of $scanned repositories could not be listed; this inventory is incomplete"
	exit 3
fi
echo "VERDICT: ok — $found worktree(s) under '$ISSUE_SLUG' across $scanned repositories"
exit 0
