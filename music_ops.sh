#!/bin/bash

function add_replay_gain_flac() {
	local TMPSCRIPT="/tmp/replay_gain.sh"

	cat > "$TMPSCRIPT" <<"EOF"
echo "metaflac --add-replay-gain: '$1'"
exec metaflac --add-replay-gain "$1"/*.flac
EOF
	chmod +x "$TMPSCRIPT"

	find . -iname '*.flac' -printf '%h\n' | sort -u | parallel "$TMPSCRIPT {}"

	rm "$TMPSCRIPT"
}

function add_replay_gain_mp3() {
	local TMPSCRIPT="/tmp/replay_gain.sh"

	cat > "$TMPSCRIPT" <<"EOF"
echo "mp3gain: '$1'"
exec mp3gain "$1"/*.mp3
EOF
	chmod +x "$TMPSCRIPT"

	find . -iname '*.mp3' -printf '%h\n' | sort -u | parallel "$TMPSCRIPT {}"

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
	       -not \( -iname '*.flac' -or -iname '*.mp3' \) \
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
	find "${1:-.}" -iname '*.flac' \
		-exec bash -c "exec mkdir -pv \"\$(dirname \"${2:-.}/{}\")\" >&2" \; \
		-print0 | parallel -0 -N1 flac -f -8 {} -o "\"${2:-.}/\"{}"
}
