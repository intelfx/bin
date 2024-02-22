#!/bin/bash

. lib.sh || exit
shopt -s extglob

#
# constants, functions
#

GIT_MASTER_NAMES=(
	master
	main
)

git_verify() {
	git rev-parse --verify --quiet "$1" >/dev/null
}

git_head() {
	local rev
	rev="$(git rev-parse --symbolic-full-name HEAD)"
	if [[ $rev == HEAD ]]; then
		# detached
		rev="$(git rev-parse HEAD)"
	fi
	echo "$rev"
}


#
# args
#

_usage() {
	cat <<EOF
Usage: $0 <onto> <branch>...
EOF
}

if ! (( $# >= 1 )); then
	usage "Expected 1 or more arguments"
fi

ONTO="$1"
BRANCHES=( "${@:2}" )
ORIG=


#
# cleanup setup
#

eval "$(globaltraps)"

restore() {
	local cur
	cur="$(git_head)"
	if [[ $ORIG && $cur != $ORIG ]]; then
		git checkout "${ORIG#refs/heads/}"
	fi
}
ltrap restore


#
# setup
#

if ! git diff-index --quiet HEAD; then
	die "Working tree is dirty"
fi

ORIG="$(git_head)"

if (( ${#BRANCHES[@]} == 0 )); then
	if [[ $ORIG == refs/heads/* ]]; then
		BRANCHES+=( "${ORIG#refs/heads/}" )
		warn "Using checked out branch: $BRANCHES"
	else
		usage "No branches specified and HEAD is not on a branch"
	fi
fi

for b in "${GIT_MASTER_NAMES[@]}"; do
	if git_verify "$b@{u}"; then
		UPSTREAM="$(git rev-parse --symbolic-full-name "$b@{u}")"
		UPSTREAM="${UPSTREAM#refs/remotes/}"
		break
	fi
done

if ! [[ ${UPSTREAM+set} ]]; then
	die "Could not infer master branch and its upstream"
fi


#
# actual operation
#

SUFFIX="${ONTO##*(*/)?(v)}"
DEST="work/patches-$SUFFIX"
log "Target branch: $DEST"

TARGET="$(git rev-parse --short "$ONTO")"
log "Starting point: $ONTO ($TARGET)"

for b in "${BRANCHES[@]}"; do
	log "Picking $UPSTREAM..$b"
	rev="$(git rev-parse "$b")"

	# see if $b has already been merged into upstream
	if git merge-base --is-ancestor "$b" "$UPSTREAM"; then
		warn "Applying hack: $b is ancestor of $UPSTREAM"

		git log --first-parent --format="%H %P" "$UPSTREAM" \
		| awk -v rev="$rev" '$3 == rev { print $1; exit }' \
		| read mergepoint \
			|| true
		if ! [[ $mergepoint ]]; then
			die "Hack failed: failed to find merge point of $UPSTREAM and $b"
		fi

		mergeparent="$(git rev-parse "$mergepoint^1")"
		if git merge-base --is-ancestor "$b" "$mergeparent"; then
			die "Hack failed: $b is still an ancestor of $mergeparent"
		fi

		mergebase="$(git merge-base "$b" "$mergeparent")"
		git rebase-repeatedly --reapply-cherry-picks --onto "$TARGET" "$mergeparent" "$rev"
	else
		git rebase-repeatedly --reapply-cherry-picks --onto "$TARGET" "$UPSTREAM" "$rev"
	fi

	old="$TARGET"
	TARGET="$(git rev-parse --short HEAD)"
	log "OK ($old..$TARGET)"
done
log "All done ($TARGET), committing result"

git branch -f "$DEST" "$TARGET"
log "All done: $DEST ($TARGET)"
