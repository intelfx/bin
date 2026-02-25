#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=../lib/lib.sh
. lib.sh

# FFMPEG=(ffpb)
# FFMPEG=(~/tmp/big/ffpb-rs/target/release-lto/ffpb)
# FFMPEG=(node ~/tmp/big/ffmpeg-progressbar-cli/lib/main.js)
FFMPEG=(ffmpeg)

# OUTPUT_SUFFIX=".out.h264"
# FFMPEG_V_ARGS=(
# 	-c:v libx264
# 	-crf:v 17
# 	-preset:v medium
# 	# -profile:v high
# 	-movflags +faststart
# )
# FFMPEG_V_PASS1_ARGS=(
# 	-pass:v 1
# )
# FFMPEG_V_PASS2_ARGS=(
# 	-pass:v 2
# )
# FFMPEG_A_ARGS=(
# 	-c:a copy
# )
# FFMPEG_2PASS=0

OUTPUT_SUFFIX=".out.h265"
FFMPEG_V_ARGS=(
	-c:v libx265
	-crf:v 17
	-preset:v medium
	# -profile:v high
	-movflags +faststart
)
FFMPEG_V_PASS1_ARGS=(
	-x265-params pass=1
)
FFMPEG_V_PASS2_ARGS=(
	-x265-params pass=2
)
FFMPEG_A_ARGS=(
	-c:a copy
)
FFMPEG_2PASS=0

INPUT="$1"
[[ -f $INPUT ]] || die "Bad input: ${INPUT@Q}"

shopt -s extglob
stem="${INPUT%.+([^./])}"
ext="${INPUT#"$stem"}"
OUTPUT="${stem}${OUTPUT_SUFFIX}${ext}"
LOG="$OUTPUT.log"

log "Input: ${INPUT@Q}"
log "Output: ${OUTPUT@Q}"

if (( FFMPEG_2PASS )); then
	set -x
	"${FFMPEG[@]}" -y -i "$INPUT" "${FFMPEG_V_ARGS[@]}" "${FFMPEG_V_PASS1_ARGS[@]}" -passlogfile "$LOG" -an                   -f null /dev/null
	"${FFMPEG[@]}" -y -i "$INPUT" "${FFMPEG_V_ARGS[@]}" "${FFMPEG_V_PASS2_ARGS[@]}" -passlogfile "$LOG" "${FFMPEG_A_ARGS[@]}" "$OUTPUT"
else
	set -x
	"${FFMPEG[@]}" -y -i "$INPUT" "${FFMPEG_V_ARGS[@]}"                             "${FFMPEG_A_ARGS[@]}" "$OUTPUT"
fi
