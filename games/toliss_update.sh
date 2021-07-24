#!/bin/bash

set -eo pipefail
shopt -s lastpipe
shopt -s extglob

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

UPDATE_DIRS=(
	"/mnt/c/Games/X-Plane 11/Aircraft/ToLiSS"
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

declare -A TOLISSES

for basedir in "${UPDATE_DIRS[@]}"; do
	for d in "$basedir"/*; do
		d="$(basename "$d")"
		if [[ $d =~ (.*)_([Vv]([0-9Pp]+))_* ]]; then
			toliss_model="${BASH_REMATCH[1]}"
			toliss_version="${BASH_REMATCH[2]}"

			toliss_version_nr="${toliss_version}"
			toliss_version_nr="${toliss_version_nr#+([Vv])}"
			toliss_version_nr="${toliss_version_nr//@([Pp])/.}"
			log "Processing: $d ($toliss_model, $toliss_version, $toliss_version_nr)"
		else
			die "Bad directory: $d"
		fi
	done
done
