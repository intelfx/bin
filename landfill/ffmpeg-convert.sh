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

FFMPEG_I_ARGS=(
	-f rawvideo -pix_fmt yuv420p -s 3840x2160 -r 60
)

X265_PARAMS=(
	# --level-idc=5.1
	# --high-tier
	# --min-cu-size=8
	# --rect=1
	# --amp=1
	# --tu-intra-depth=4
	# --tu-inter-depth=4
	# --ref=16
	# --bframes=16
	# --b-pyramid=1
	# --weightp=1
	# --weightb=1
	# --wpp=0
	# --slices=1
	# --sao=1
	# --deblock=1
	# --rdoq-level=2
	# --vbv-bufsize=36000
	# --vbv-maxrate=20000
	--vbv-bufsize=160000
	--vbv-maxrate=160000
)
IFS=:; X265_PARAMS_STR="${X265_PARAMS[*]}"; unset IFS

OUTPUT_SUFFIX=".out.h265"
FFMPEG_V_ARGS=(
	-c:v libx265
	-crf:v 17
	-profile:v main
	-preset:v slow
	# -x265-params "$X265_PARAMS_STR"
)
FFMPEG_V_PASS1_ARGS=(
	-x265-params "pass=1:$X265_PARAMS_STR"
)
FFMPEG_V_PASS2_ARGS=(
	-x265-params "pass=2:$X266_PARAMS_STR"
)
FFMPEG_A_ARGS=(
	-c:a copy
)
FFMPEG_2PASS=1

INPUT="$1"
[[ -f $INPUT ]] || die "Bad input: ${INPUT@Q}"

shopt -s extglob
stem="${INPUT%.+([^./])}"
ext="${INPUT#"$stem"}"
OUTPUT="${stem}${OUTPUT_SUFFIX}.mp4"
LOG="$OUTPUT.log"

log "Input: ${INPUT@Q}"
log "Output: ${OUTPUT@Q}"

if (( FFMPEG_2PASS )); then
	set -x
	"${FFMPEG[@]}" -y "${FFMPEG_I_ARGS[@]}" -i "$INPUT" "${FFMPEG_V_ARGS[@]}" "${FFMPEG_V_PASS1_ARGS[@]}" -passlogfile "$LOG" -an                   -f null /dev/null
	"${FFMPEG[@]}" -y "${FFMPEG_I_ARGS[@]}" -i "$INPUT" "${FFMPEG_V_ARGS[@]}" "${FFMPEG_V_PASS2_ARGS[@]}" -passlogfile "$LOG" "${FFMPEG_A_ARGS[@]}" "$OUTPUT"
else
	set -x
	"${FFMPEG[@]}" -y "${FFMPEG_I_ARGS[@]}" -i "$INPUT" "${FFMPEG_V_ARGS[@]}"                             "${FFMPEG_A_ARGS[@]}" "$OUTPUT"
fi
