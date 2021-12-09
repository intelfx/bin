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
	"/mnt/c/Games/Steam/steamapps/common/X-Plane 11/Aircraft/ToLiSS"
)

parse_dir() {
	local dir="$1"

	if [[ $dir =~ (.*)_([Vv]([0-9Pp]+))_* ]]; then
		toliss_model="${BASH_REMATCH[1]}"
		toliss_version_str="${BASH_REMATCH[2]}"

		toliss_version_nr="${toliss_version_str}"
		toliss_version_nr="${toliss_version_nr#+([Vv])}"
		toliss_version_nr="${toliss_version_nr//@([Pp])/.}"
		return 0
	else
		return 1
		die "Bad directory: $d"
	fi
}

process_dir() {
	local old="$1" new="$2"

	log "Moving: old=${old##*/}, new=${new##*/}"
	#comm -3 <(find "$old" -type f -printf '%P\n' | sort) <(find "$new" -type f -printf '%P\n' | sort)

	# move prefs
	#cp -av "$old"/*_prefs.txt -t "$new"
	for f in "$old"/*_prefs.txt; do
		if [[ -f "$f" ]]; then
			echo "XP11 prefs: $f"
			cp -av "$f" -t "$new"
		fi
	done

	# move liveries
	for l in "$old/liveries"/*; do
		if [[ -d "$l" ]] && ! [[ -d "$new/liveries/${l##*/}" ]]; then
			echo "livery: $l"
			cp -av "$l" -t "$new/liveries"
		fi
	done

	# move prefs and license
	for f in "$old"/plugins/AirbusFBW_*/*.prf; do
		fdir="${f%/*}"; fdir="${fdir#$old/}"

		if [[ -f "$f" ]]; then
			echo "plugin prefs: $f"
			cp -av "$f" -t "$new/$fdir"
		fi
	done

	for f in "$old"/plugins/AirbusFBW_*/*.lic; do
		fdir="${f%/*}"; fdir="${fdir#$old/}"

		if [[ -f "$f" ]]; then
			echo "license: $f"
			cp -av "$f" -t "$new/$fdir"
		fi
	done

	log "Deleting: old=${old##*/}"
	rm -rf "$old"
}

declare -A TOLISS_MODELS

find "${UPDATE_DIRS[@]}" -mindepth 1 -maxdepth 1 -type d | while read p; do
	d="$(basename "$p")"
	parse_dir "$d" || die "Bad directory: $d"

	log "Found: $d (model=$toliss_model, version_str=$toliss_version_str, version=$toliss_version_nr)"
	TOLISS_MODELS[$toliss_model]=1
done

for model in "${!TOLISS_MODELS[@]}"; do
	TOLISS_VERSIONS=()
	find "${UPDATE_DIRS[@]}" -mindepth 1 -maxdepth 1 -type d -name "${model}_*" | while read p; do
		d="$(basename "$p")"
		parse_dir "$d" || die "Bad directory: $d"
		
		echo "$toliss_version_nr"$'\t'"$p"
	done | sort -t $'\t' -k 1 -V | cut -d $'\t' -f 2 | readarray -t TOLISS_VERSIONS

	if (( ${#TOLISS_VERSIONS[@]} <= 1 )); then
		log "$model: nothing to do"
		continue
	elif (( ${#TOLISS_VERSIONS[@]} > 2 )); then
		err "$model: ambiguous: mode than 2 builds"
		printf -- "- %s\n" "${TOLISS_VERSIONS[@]}"
		continue
	fi

	process_dir "${TOLISS_VERSIONS[0]}" "${TOLISS_VERSIONS[-1]}"
done
