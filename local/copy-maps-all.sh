#!/bin/bash

MAPSETFILE="$HOME/tmp/igo-map-set.txt"

function read_map_set() {
	while read country; do
		echo "---- Processing country $country" >&2
		for file in "$country"*; do
			[[ -f "$file" ]] || continue

			echo "$file"
		done
	done < "$MAPSETFILE"
}

[[ -d "$1" ]] || { echo "Destination directory unset or wrong: \"$1\"" >&2; exit 1; }
kde-cp $(read_map_set) "$1"
#read_map_set
