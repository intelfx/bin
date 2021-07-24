#!/bin/bash

set -eo pipefail
shopt -s lastpipe

log() {
	echo ":: $*" >&2
}

err() {
	echo "E: $*" >&2
}

die() {
	err "$@"
	exit 1
}

ARCHIVE_TIME="2 days ago"
ARCHIVE_DIRS=(
	"/mnt/c/Users/intelfx/Documents/Flight Plans/FMS plans"
	"/mnt/c/Users/intelfx/Documents/Flight Plans/SimBrief"
)

archive_dir() {
	local dir="$1"
	log "Archiving files in directory: '$dir'"

	local file mtime
	find -L "$dir" -mindepth 1 -maxdepth 1 -type f -not -newermt "$ARCHIVE_TIME" -printf "%P\t%T@\n" \
	| while IFS=$'\t' read file mtime; do
		mtime="$(date -Idate -d "@$mtime")"
		archive_dir="$dir/archive/$mtime"

		mkdir -pv "$archive_dir"
		mv -v "$dir/$file" -t "$archive_dir"
	done
}

for d in "${ARCHIVE_DIRS[@]}"; do
	archive_dir "$d"
done
