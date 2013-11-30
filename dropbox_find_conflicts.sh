#!/bin/bash

TMPFILE=~/tmp/find_conflicts.txt
TMPDIR=~/tmp/find_conflicts
mkdir -p $TMPDIR

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
		mv "$conflict_file" "$initial_file"
		log_op "USE PRE-SYNC (mv)" "$conflict_file" "$initial_file" | tee "$TMPFILE"
	else
		install -D "$conflict_file" "$TMPDIR/$conflict_file"
		rm "$conflict_file"
		log_op "USE POST-SYNC (rm)" "$conflict_file" | tee $TMPFILE
	fi
done < <(find -L ~/Dropbox -name '*conflicted*' -print )
