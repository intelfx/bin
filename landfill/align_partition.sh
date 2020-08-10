#!/bin/bash -e

. lib.sh || exit 1

ARG_START="$1"
ARG_END="$2"
ARG_ALIGN_BYTES="$3"

log "Partition start: $ARG_START"
log "Partition end: $ARG_END"
log "Alignment (bytes): $ARG_ALIGN_BYTES"

SECTOR=512

ALIGN_SECTORS="$(( ARG_ALIGN_BYTES / SECTOR ))"
log "Alignment (sectors): $ALIGN_SECTORS"

SIZE="$(( ARG_END - ARG_START + 1 ))"
log "Partition size (sectors): $SIZE"

TAIL="$(( SIZE % ALIGN_SECTORS ))"
SIZE_ALIGNED="$(( SIZE - TAIL ))"
log "Aligned partition size: $SIZE_ALIGNED (tail: $TAIL)"

END_ALIGNED="$(( ARG_START + SIZE_ALIGNED - 1 ))"
log "Aligned partition end: $END_ALIGNED"
echo "$END_ALIGNED"
