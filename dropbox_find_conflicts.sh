#!/bin/bash

TMPFILE="$HOME/tmp/find_conflicts.txt"
TMPDIR="$HOME/tmp/find_conflicts"
mkdir -p "$TMPDIR"

function log_op() {
	echo "$1:"
	echo "    $2"
	[[ "$3" ]] && \
	echo "    $3"
	echo ""
}

while read conflict_file; do
	initial_file=${conflict_file/ ([^ ]*\'s conflicted copy*)}
	if (( FORCE )) || [ ! -f "$initial_file" ] || [ "$conflict_file" -nt "$initial_file" ]; then
		log_op "USE PRE-SYNC (mv)" "$conflict_file" "$initial_file" | tee "$TMPFILE"
		mkdir -p "$TMPDIR/$(dirname "$initial_file")"
		mv "$initial_file" "$TMPDIR/$initial_file"
		mv "$conflict_file" "$initial_file"
	else
		log_op "USE POST-SYNC (rm)" "$conflict_file" | tee $TMPFILE
		mkdir -p "$TMPDIR/$(dirname "$conflict_file")"
		mv "$conflict_file" "$TMPDIR/$conflict_file"
	fi
done < <(find -L "${1:-$HOME/Dropbox}" -iname '*conflict*' -print)
