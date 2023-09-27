#!/bin/bash

. lib.sh || exit

REMOTE_BRANCH="bcachefs/master"
REMOTE_REF="refs/remotes/$REMOTE_BRANCH"
LOCAL_TMP="bcachefs/tmp"

for d in /mnt/borg/able-2023-{06..12}*; do
	[[ "$d" =~ /(able-[^/]+) ]]; name="${BASH_REMATCH[1]}"
	log "Processing backup: $name"

	d+="/arch/home/intelfx/devel/ext/linux"
	if ! [[ -d "$d" ]] || ! git ls-remote --quiet --exit-code "$d" "$REMOTE_REF" >/dev/null; then
		continue
	fi

	git fetch --progress "$d" "$REMOTE_REF"

	major="$(git describe --tags --abbrev=0 --match 'v*.*' FETCH_HEAD)"
	local_branch="bcachefs/${major#v}"
	local_ref="refs/heads/$local_branch"

	#git fetch "$d" "+$REMOTE_REF:$local_ref"

	# just like git-fetch '+...', but do not rewind local branch
	#if ! git show-ref --verify --quiet "$local_ref" || ! git merge-base --is-ancestor FETCH_HEAD "$local_branch"; then

	# emulate git-fetch output
	old="$(git rev-parse --verify --quiet --short "$local_branch")" || true
	new="$(git rev-parse --verify --quiet --short FETCH_HEAD)"

	if ! [[ $old ]]; then
		echo "$(pad 30 " * [new branch $new]") $REMOTE_BRANCH -> $local_branch"
	elif [[ $old == $new ]]; then
		#echo "$(pad 30 "   [unchanged $old]") $REMOTE_BRANCH -> $local_branch"
		continue
	elif   git merge-base --is-ancestor FETCH_HEAD "$local_branch"; then
		echo "$(pad 30 " ! $old...$new") $REMOTE_BRANCH -> $local_branch (ancestor, not updating)"
		continue
	elif ! git merge-base --is-ancestor "$local_branch" FETCH_HEAD; then
		l="$(git rev-list --count $new..$old)"
		r="$(git rev-list --count $old..$new)"
		echo "$(pad 30 " + $old...$new") $REMOTE_BRANCH -> $local_branch (forced update, old=$l, new=$r)"
	else
		echo "$(pad 30 "   $old..$new") $REMOTE_BRANCH -> $local_branch"
	fi

	git branch -f "$local_branch" FETCH_HEAD

	#fi
done
