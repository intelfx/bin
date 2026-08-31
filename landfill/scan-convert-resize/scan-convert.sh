#!/bin/bash

set -exo pipefail
shopt -s extglob

IN="$1"
OUT="$2"

NR="$IN"
NR="${NR##*/}"
NR="${NR%%.*}"
NR="${NR##+(0)}"

mkdir -p "$(dirname "$OUT")"

vips colourspace "$IN" "$OUT.tmp1.pgm" b-w
cjpegli -d 1 "$OUT.tmp1.pgm" "$OUT"
#cjpeg -grayscale -q 90 -outfile "$OUT" "$OUT.tmp1.pgm"
rm -f "$OUT".tmp*
