#!/bin/bash

DISK="$1"

[ -b "$DISK" ] || { echo "Invalid disk supplied: \"$DISK\"" >&2; exit 1; }

DISK_SIZE="$(< /sys/block/"$(basename $DISK)"/size )"

declare -a TRIM_RANGES

function perform_trim() {
	local TRIM_RANGE_LENGTH="$(( $TRIM_RANGE_END - $TRIM_RANGE_START + 1 ))"
	local WILL_NOW_TRIM
	echo "-- Recording trimmed ranges: $TRIM_RANGE_START to $TRIM_RANGE_END (length: $TRIM_RANGE_LENGTH)"

	while (( "$TRIM_RANGE_LENGTH" > 0 )); do
		(( "$TRIM_RANGE_LENGTH" > 65535 )) && WILL_NOW_TRIM="65535" || WILL_NOW_TRIM="$TRIM_RANGE_LENGTH"
#		echo " - Trimming: range $TRIM_RANGE_START length $WILL_NOW_TRIM"
		TRIM_RANGES+=( "$TRIM_RANGE_START:$WILL_NOW_TRIM" )

		(( TRIM_RANGE_START += WILL_NOW_TRIM ))
		(( TRIM_RANGE_LENGTH -= WILL_NOW_TRIM ))
	done
}

TRIM_RANGE_START="0"
TRIM_RANGE_END="$(( DISK_SIZE - 1 ))"
perform_trim

echo ""

if ! (( CONFIRM_DESTROY )); then
	echo "-- Not issuing trim of ${#TRIM_RANGES[@]} range(s), pass CONFIRM_DESTROY=1 to perform actions"
else
	echo "-- Issuing trim of ${#TRIM_RANGES[@]} range(s)"

	for range in "${TRIM_RANGES[@]}"; do
		echo "$range"
	done | hdparm --trim-sector-ranges-stdin --please-destroy-my-drive "$DISK"
fi
