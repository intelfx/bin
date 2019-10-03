#!/bin/bash

: ${MAPVENDOR:=NQ}

MAPSETFILE="$HOME/tmp/igo-map-set.txt"

function read_map_set() {
	while read country; do
		echo "---- Processing country $country (vendor $MAPVENDOR)" >&2
		(
		declare -A years
		declare -A files
		for file in "$country"*"$MAPVENDOR"*; do
			[[ -e "$file" ]] || continue

			YEAR="$(grep -oE '20[0-9]{2}' <<< "$file")"
			EXT="$(grep -oE '\.[^.]*$' <<< "$file")"

			echo -n " - Trying extension \"$EXT\" of year $YEAR" >&2
			if [[ -z "${years[$EXT]}" ]] || (( "${years[$EXT]}" < "$YEAR" )); then
				echo " - accepted" >&2
				years[$EXT]="$YEAR"
				files[$EXT]="\"$file\""
			elif (( "${years[$EXT]}" == "$YEAR" )); then
				echo " - appended" >&2
				files[$EXT]+=" \"$file\""
			else
				echo "" >&2
			fi
		done

		echo "${files[@]}"
		)
	done < "$MAPSETFILE"
}

[[ -d "$1" ]] || { echo "Destination directory unset or wrong: \"$1\"" >&2; exit 1; }

# Put filenames in array, honoring double-quotes to handle names with spaces
eval "FILES=( $(read_map_set) )"

kde-cp "${FILES[@]}" "$1"
