#!/bin/bash
source ~/bin/framework/framework || exit 1

CONVERT_FORMATS=( "flac" "m4a" )
COPY_FORMATS=( "mp3" "ogg" "aac" )

INPUT="$1"
[[ -r "$INPUT" ]] || exit_err "Could not read input: '$(i_e "$INPUT")'"

OUTPUT="$2"
[[ -d "$OUTPUT" ]] || exit_err "Output is not a directory: '$(i_e "$OUTPUT")'"

PREPARED="${INPUT}.tmp"
TO_CONVERT="${INPUT}.to-convert"
TO_COPY="${INPUT}.to-copy"
grep -vE '^#' "$INPUT" > "$PREPARED"

CONVERT_SCRIPT="convert_script.sh"
cat > "$CONVERT_SCRIPT" <<"EOF"
#!/bin/bash

IN="$2"
OUT="$2"
OUT="$1/${OUT##*/}"
OUT="${OUT%.*}"

OUT_EXT="m4a"

OUT_TMP="$(mktemp "$OUT.$OUT_EXT-XXXXXX")"

function cleanup() {
	rm -f "$OUT_TMP"
}

trap cleanup EXIT

echo -n "$IN ... "
{ ffmpeg -i "$IN" -f caf - | fdkaac -m 5 -w 20000 - -o "$OUT_TMP"; } &>/dev/null

mv -n "$OUT_TMP" "$OUT.$$-$RANDOM.$OUT_EXT"
echo "done"
EOF
chmod +x "$CONVERT_SCRIPT"

COPY_SCRIPT="copy_script.sh"
cat > "$COPY_SCRIPT" <<"EOF"
#!/bin/bash

IN="$2"
OUT="$2"
OUT="$1/${OUT##*/}"
OUT_EXT="${OUT##*.}"
OUT="${OUT%.*}"

cp -v "$IN" "$OUT.$$-$RANDOM.$OUT_EXT"
EOF
chmod +x "$COPY_SCRIPT"

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

files_by_formats "$PREPARED" "${CONVERT_FORMATS[@]}" > "$TO_CONVERT"
files_by_formats "$PREPARED" "${COPY_FORMATS[@]}" > "$TO_COPY"

function process_and_pv() {
	local FILE_LIST="$1"
	local NAME="$2"
	shift 2

	local FILE_COUNT="$(wc -l < "$FILE_LIST")"

	xargs -d$'\n' --arg-file "$FILE_LIST" "$@" | pv -N "$NAME ($FILE_COUNT files)" -pbate -W -c -s "$FILE_COUNT" -l >/dev/null
}

process_and_pv "$TO_COPY" "copying" -n1 -P1 ./"$COPY_SCRIPT" "$OUTPUT" &
process_and_pv "$TO_CONVERT" "converting" -n1 -P8 ./"$CONVERT_SCRIPT" "$OUTPUT" &
wait

rm -vf "$PREPARED" "$TO_COPY" "$TO_CONVERT" "$CONVERT_SCRIPT" "$COPY_SCRIPT"
