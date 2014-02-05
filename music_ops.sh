#!/bin/bash

function add_replay_gain() {
	local TMPSCRIPT="/tmp/replay_gain.sh"

	cat > "$TMPSCRIPT" <<"EOF"
echo "metaflac --add-replay-gain: '$1'"
exec metaflac --add-replay-gain "$1"/*.flac
EOF
	chmod +x "$TMPSCRIPT"

	find . -iname '*.flac' -printf '%h\n' | sort -u | parallel "$TMPSCRIPT {}"

	rm "$TMPSCRIPT"
}

function split() {
	while read -u 9 dir; do
		split2flac "$dir"
	done 9< <(find . -iname '*.cue' -printf '%h\n' | sort -u)
}

function cleanup() {
	echo "== cleanup: removing non-media files"
	find . -type f \
	       -not -iname '*.flac' \
	       -print -delete

	echo "== cleanup: merging soundkonverter suffixed files"
	find . -iname '*.новый*' | while read file; do
		echo "$file"
		mv "$file" "${file//.новый}" || break
	done

	echo "== cleanup: removing empty directories"
	find . -type d \
	       -empty \
	       -print -delete
}

function reflac() {
	find . -iname '*.flac' -print0 | parallel -0 flac -f -8 {}
}
