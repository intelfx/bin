#!/bin/bash

. lib.sh || exit 1

ARG_FORCE=0
if [[ $1 == --force ]]; then
	ARG_FORCE=1
	shift
fi

rc=0
for dir; do
	if ! [[ -d "$dir" ]]; then
		err "$dir: not a directory, skipping"
		rc=1
	fi
	most_recent_mtime="$(find "$dir" -mindepth 1 -maxdepth 1 -printf '%T@\n' | sort -n | tail -n1)" || { rc=1; continue; }
	if ! [[ "$most_recent_mtime" ]]; then
		if (( ARG_FORCE )); then
			log "$dir: no files, resetting to epoch"
			most_recent_mtime=0
		else
			log "$dir: no files, skipping"
			continue
		fi
	fi
	touch -d "@$most_recent_mtime" "$dir" || { rc=1; continue; }
done
exit $rc
