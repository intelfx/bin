#!/bin/bash

set -eo pipefail
shopt -s lastpipe

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

if ! (( $# == 2 )); then
	die "Expected 2 arguments, got $# (usage: $0 <target version> <branch>)"
fi

BASE="$1"
BRANCH="$2"

if ! git_verify "$BASE"; then
	die "Invalid base: $BASE"
fi

if ! git_verify "$BRANCH"; then
	die "Invalid branch to rebase: $BRANCH"
fi

log "Target base version: $BASE"
log "Branch: $BRANCH"

if ! OLD_BASE="$(git_find_base_version "$BRANCH")"; then
	die "Unable to determine old base"
fi

log "Existing base version: $OLD_BASE"

NEW_BRANCH="${BRANCH%-${OLD_BASE#v}}-${BASE#v}"

log "New branch: $NEW_BRANCH"

if git_verify "$NEW_BRANCH"; then
	die "New branch ($NEW_BRANCH) exists, aborting"
fi

git branch -f "$NEW_BRANCH" "$BRANCH"
git rebase --onto "$BASE" "$OLD_BASE" "$NEW_BRANCH"
