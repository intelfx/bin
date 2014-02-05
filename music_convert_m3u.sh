#!/bin/bash
source ~/bin/framework/framework || exit 1

CONVERT_FORMATS=( "flac" "m4a" )
COPY_FORMATS=( "mp3" "ogg" "aac" )

INPUT="$1"
[[ -r "$INPUT" ]] || exit_err "Could not read input: '$(i_e "$INPUT")'"

OUTPUT="$2"
[[ -d "$OUTPUT" ]] || exit_err "Output is not a directory: '$(i_e "$OUTPUT")'"

PREPARED="${INPUT}.tmp"
grep -vE '^#' "$INPUT" > "$PREPARED"

function lines_by_format() {
	grep -iE "\\.${2}$" "${1}"
}

decode() {
	while read line; do
		rawurldecode "$line"$'\n'
	done
}

files_by_formats() {
	for format; do
		lines_by_format "$1" "$format" | decode
	done
}

echo "doing convert..."
files_by_formats "$PREPARED" "${CONVERT_FORMATS[@]}" | xargs -d$'\n' soundkonverter --output "$OUTPUT"

echo "doing cp..."
files_by_formats "$PREPARED" "${COPY_FORMATS[@]}" | xargs -d$'\n' cp -t "$OUTPUT"

rm "$PREPARED"
