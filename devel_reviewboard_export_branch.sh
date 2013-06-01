#!/bin/bash

BASEDIR="$(pwd)"
BASENAME="$(basename $BASEDIR)"
OUTDIR="$HOME/devel/patches/export/$BASENAME"

pushd $BASEDIR

function ver_branch() {
	echo "-- Verifying presence of branch $1"
	git branch | grep -q "$1"
	if (( $? )); then
		echo " * branch $1 not found!"
		return 1
	else
		return 0
	fi
}

function do_diff {
	local NAME=${3:-$2}
	echo "-- Diffing: $1..$2 to $NAME"
	mkdir -p $OUTDIR
	[ "$FULLDIFF" ] && git format-patch $1..$2 -o "$OUTDIR/$NAME"
	git diff $1..$2 > "$OUTDIR/$NAME.patch"
}

function do_export_branch {
	local BRANCH
	BRANCH="$1"

	echo "-- Exporting branch $BRANCH"

	ver_branch $BRANCH

	if [ "$BRANCH" = "master" ]; then
		ver_branch origin/master
		do_diff origin/master master
	else
		ver_branch $BASEBRANCH

		if [ "$BASEBRANCH" != "master" ]; then
			do_diff master $BASEBRANCH "$BRANCH-base"
		fi
	fi
	do_diff $BASEBRANCH $BRANCH

	echo ""
}

BASEBRANCH="$1"
shift

for branch; do do_export_branch "$branch"; done

echo "-- Done"
popd
