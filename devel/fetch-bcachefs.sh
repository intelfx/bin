#!/bin/bash

. lib.sh || exit

git_verify() {
	git rev-parse --verify --quiet "$1" >/dev/null
}

REMOTE_NAME="bcachefs"
REMOTE_BRANCH="bcachefs/master"
REMOTE_REF="refs/remotes/$REMOTE_BRANCH"

git fetch --progress "$REMOTE_NAME"
major="$(git describe --tags --abbrev=0 --match 'v*.*' --exclude '*.*.*' "$REMOTE_BRANCH")"
if ! [[ $major =~ ^v[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]]; then
	die "Bad describe: $major"
fi
major="${major#v}"
major="${major%-rc*}"
local_branch="bcachefs-hist/$major"
local_ref="refs/heads/$local_branch"

# emulate git-fetch output
old="$(git rev-parse --verify --quiet --short "$local_branch")" || true
new="$(git rev-parse --verify --quiet --short "$REMOTE_BRANCH")"

if ! [[ $old ]]; then
	echo "$(pad 30 " * [new branch $new]") $REMOTE_BRANCH -> $local_branch"
elif [[ $old == $new ]]; then
	#echo "$(pad 30 "   [unchanged $old]") $REMOTE_BRANCH -> $local_branch"
	exit
elif   git merge-base --is-ancestor FETCH_HEAD "$local_branch"; then
	echo "$(pad 30 " ! $old...$new") $REMOTE_BRANCH -> $local_branch (ancestor, not updating)"
	exit
elif ! git merge-base --is-ancestor "$local_branch" FETCH_HEAD; then
	l="$(git rev-list --count $new..$old)"
	r="$(git rev-list --count $old..$new)"
	echo "$(pad 30 " + $old...$new") $REMOTE_BRANCH -> $local_branch (forced update, old=$l, new=$r)"
else
	echo "$(pad 30 "   $old..$new") $REMOTE_BRANCH -> $local_branch"
fi

git branch --no-track -f "$local_branch" "$REMOTE_BRANCH"
