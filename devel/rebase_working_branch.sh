#!/bin/bash

. lib.sh || exit

git_verify() {
	git rev-parse --verify --quiet "$1" >/dev/null
}

git_find_base_version() {
	git describe \
		--tags \
		--abbrev=0 \
		--match 'v*.*' \
		--exclude 'v*.*-*' \
		"$@"
		#--exclude 'v*.*.*' \
}

_usage() {
	cat <<EOF
Usage: $0 <onto> <branch>...
EOF
}

if ! (( $# >= 2 )); then
	usage "Expected 2 or more arguments"
fi

BASE="$1"
BRANCHES=( "${@:2}" )

if ! git_verify "$BASE"; then
	die "Invalid base: $BASE"
fi

rc=0
for BRANCH in "${BRANCHES[@]}"; do
	if ! git_verify "$BRANCH"; then
		die "Invalid branch to rebase: $BRANCH"
	fi

	log "Target base version: $BASE"
	log "Branch: $BRANCH"

	if ! OLD_BASE="$(git_find_base_version "$BRANCH")"; then
		err "Unable to determine old base"
		rc=1
		continue
	fi

	log "Existing base version: $OLD_BASE"

	NEW_BRANCH="${BRANCH%-${OLD_BASE#v}}-${BASE#v}"

	log "New branch: $NEW_BRANCH"

	if git_verify "$NEW_BRANCH"; then
		err "New branch ($NEW_BRANCH) exists, aborting"
		rc=1
		continue
	fi

	git branch -f "$NEW_BRANCH" "$BRANCH"
	git rebase --onto "$BASE" "$OLD_BASE" "$NEW_BRANCH"
done

exit $rc
