#!/bin/bash

. lib.sh || exit

ARGS=$(getopt -o 'a:' --long 'align:' -n "${0##*/}" -- "$@")
eval set -- "$ARGS"
unset ARGS

ALIGNMENT=1048576
SECTOR_BYTES=512

usage() {
	die "Usage: TODO"
}

parse_bytes() {
	local in="$1"
	local number unit scale
	if ! [[ $in =~ ^([0-9]+)([a-zA-Z]*)$ ]]; then
		return 1
	fi
	number="${BASH_REMATCH[1]}"
	unit="${BASH_REMATCH[2]}"

	case "$unit" in
	s|sec)
		(( number *= SECTOR_BYTES )) ;;
	''|[bB])
		;;
	[kK]|KiB)
		(( number *= 1024 )) ;;
	[mM]|MiB)
		(( number *= 1024*1024 )) ;;
	[gG]|GiB)
		(( number *= 1024*1024*1024 )) ;;
	*)
		err "Invalid unit: $unit (supported 's', 'K', 'M', 'G')"
		return 1 ;;
	esac

	echo "$number"
}

while :; do
	case "$1" in
	-a|--align)
		ALIGNMENT="$2"
		shift 2
		;;
	-s|--sector-size)
		SECTOR_BYTES="$2"
		shift 2
		;;
	'--')
		shift
		break
		;;
	*)
		die "Internal error"
		;;
	esac
done

if ! (( $# == 2 )); then
	err "Wrong number of positional arguments (expected 2, got $#)"
	usage
fi

START_SEC="$1" # first usable sector
END_SEC="$2" # last usable sector

if ! ALIGNMENT_BYTES="$(parse_bytes "$ALIGNMENT")"; then
	err "Invalid alignment value: $ALIGNMENT_BYTES"
	usage
fi

log "Start (sector):	$START_SEC"
log "End (sector):	$END_SEC"

LENGTH_SEC="$(( END_SEC - START_SEC + 1 ))"
log "Length (sectors):	$LENGTH_SEC"

LENGTH_BYTES="$(( LENGTH_SEC * SECTOR_BYTES ))"
LENGTH_BYTES_TAIL="$(( LENGTH_BYTES % ALIGNMENT_BYTES ))"
log "Length (bytes):	$LENGTH_BYTES ($LENGTH_BYTES_TAIL bytes tail, aligned to $ALIGNMENT_BYTES bytes)"

ALIGNED_LENGTH_BYTES="$(( LENGTH_BYTES - LENGTH_BYTES_TAIL ))"
log "Aligned length (bytes):	$ALIGNED_LENGTH_BYTES"
ALIGNED_LENGTH_SEC="$(( ALIGNED_LENGTH_BYTES / SECTOR_BYTES ))"
ALIGNED_LENGTH_SEC_TAIL="$(( ALIGNED_LENGTH_BYTES % SECTOR_BYTES ))"
if (( ALIGNED_LENGTH_SEC_TAIL > 0 )); then
	die "Aligned length is not a multiple of sector size: $ALIGNED_LENGTH_SEC_TAIL bytes remainder"
fi
log "Aligned length (sectors):	$ALIGNED_LENGTH_SEC"

ALIGNED_END_SEC="$(( START_SEC + ALIGNED_LENGTH_SEC - 1 ))"
if [[ -t 1 && -t 2 ]]; then
	log "Aligned end (sectors):	$ALIGNED_END_SEC"
else
	echo "$ALIGNED_END_SEC"
fi
