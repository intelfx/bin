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
	"/mnt/c/Games/Steam/steamapps/common/X-Plane 11/Output:*.png"
)

ARCHIVE_DEST=(
	# WSL and Windows symlinks to network drives are mutually incompatible, consider an override
	archive.wsl
	archive
)

archive_dir() {
	if [[ "$1" == *:* ]]; then
		local dir="${1%:*}"
		local mask="${1#*:}"
	else
		local dir="$1"
		local mask=""
	fi

	if [[ "$mask" ]]; then
		mask_arg=( -name "$mask" )
	else
		mask_arg=()
	fi

	local dest
	for dest in "${ARCHIVE_DEST[@]}"; do
		# find first valid destination
		dest="$(cd "$dir"; realpath -qm "$dest")"
		if [[ -d "$dest" ]]; then
			break
		fi
	done
	if ! [[ -d "$dest" ]]; then
		err "[$dir] Could not find a valid archival destination"
	fi
	log "[$dir] Archiving ${mask:-all} files to $dest"

	local file mtime
	find -L "$dir" -mindepth 1 -maxdepth 1 -type f "${mask_arg[@]}" -not -newermt "$ARCHIVE_TIME" -printf "%P\t%T@\n" \
	| while IFS=$'\t' read file mtime; do
		mtime="$(date -Idate -d "@$mtime")"
		archive_dir="$dest/$mtime"
		mkdir -pv "$archive_dir"
		mv -v "$dir/$file" -t "$archive_dir"
	done
}

for d in "${ARCHIVE_DIRS[@]}"; do
	archive_dir "$d"
done
