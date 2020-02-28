#!/bin/bash -e

. lib.sh || exitG

MKTORRENT=(
	mktorrent
	--verbose
	--private
	--source RED
	--announce "$(pass misc/redacted.ch/intelfx/announce)"
)

FILES=( "$@" )

if (( ${#FILES[@]} < 1 )); then
	die "Bad file list: ${FILES[*]}"
elif (( ${#FILES[@]} == 1 )); then
	NAME="${FILES[0]//\//-}.torrent"
	log "Creating torrent: $NAME"
else
	NAME="files-$(date -Iseconds).torrent"
	warn "Multiple files specified, falling back to non-descriptive name: $NAME"
fi
MKTORRENT+=(
	-o "$NAME"
)

SIZE="$(/usr/bin/du --bytes --summarize --total "${FILES[@]}" | tail -n1 | cut -d $'\t' -f1)"

calc_order() {
	local order="$1"
	piece=$(( 2 ** order ))
	pieces=$(( (SIZE+piece-1) / piece ))
}

perfect=
small=
large=
log "Torrent size $SIZE bytes"
for (( order=15; order <= 21; ++order )); do
	calc_order $order
	if (( pieces > 1500 )); then
		dbg "Piece size too small: 2^$order=$piece, total $pieces > 1500"
		small=$order
	elif (( pieces < 1000 )); then
		dbg "Piece size too large: 2^$order=$piece, total $pieces < 1000"
		if ! [[ $large ]]; then
			large=$order
		fi
	elif (( pieces >= 1000 && pieces <= 1500 )); then
		dbg "Candidate piece size: 2^$order=$piece, total $pieces"
		if ! [[ $perfect ]]; then
			perfect=$order
		fi
	fi
done

if [[ $perfect ]]; then
	calc_order $perfect
	log "Smallest perfect piece size: 2^$perfect=$piece, total $pieces"
	found=$perfect
else
	calc_order $small
	small_sz=$piece
	small_p=$pieces
	calc_order $large
	large_sz=$piece
	large_p=$pieces

	if (( (small_p - 1500) < (1000 - large_p) )); then
		log "Choosing small piece over large: 2^$small=$small_sz, total $small_p (vs 2^$large=$large_sz, total $large_p)"
		found=$small
	else
		log "Choosing large piece over small: 2^$large=$large_sz, total $large_p (vs 2^$small=$small_sz, total $small_p)"
		found=$large
	fi
fi


if ! [[ $found ]]; then
	die "Cannot determine piece size"
fi
MKTORRENT+=( --piece-length $found )

exec "${MKTORRENT[@]}" "${FILES[@]}"
