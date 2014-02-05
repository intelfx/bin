#!/bin/bash

DISK="$1"

[ -b "$DISK" ] || { echo "Invalid disk supplied: \"$DISK\"" >&2; exit 1; }

REGEX_SEC_BOUNDARIES="^First usable sector is ([[:digit:]]*), last usable sector is ([[:digit:]]*)$"

REGEX_TABLE_HEADERS="^Number "

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

function parse_range() {
	TRIM_RANGE_START="$(( $LAST_USED + 1 ))"
	TRIM_RANGE_END="$(( $PART_START - 1 ))"

	echo "    * free space (non-inclusive): $LAST_USED to $PART_START"
	echo "    * used space (inclusive):     $PART_START to $PART_END"

	if (( "$TRIM_RANGE_START" <= "$TRIM_RANGE_END" )); then
		perform_trim
	else
		echo "-- Won't trim: $TRIM_RANGE_START to $TRIM_RANGE_END"
	fi

	LAST_USED="$PART_END"
}

while read line; do

	if (( "$PARSE_TABLE" )); then
		read PART_NR PART_START PART_END _ <<< "$line"

		echo ""
		echo "-- Handling partition $PART_NR"

		parse_range
	fi

	if grep -Eq "$REGEX_SEC_BOUNDARIES" <<< "$line"; then
		read DISK_START DISK_END < <(echo "$line" | sed -re "s|$REGEX_SEC_BOUNDARIES|\1 \2|")
	fi

	if grep -Eq "$REGEX_TABLE_HEADERS" <<< "$line"; then
		PARSE_TABLE=1
		LAST_USED="$(( $DISK_START - 1 ))"
	fi

done < <(LC_ALL=C gdisk -l "$DISK")

echo ""
echo "-- Handling free space after last partition"

PART_START="$(( $DISK_END + 1 ))"
parse_range

echo ""
echo "-- Issuing trim of ${#TRIM_RANGES[@]} range(s)"

(( CONFIRM )) || exit

for range in "${TRIM_RANGES[@]}"; do
	echo "$range"
done | hdparm --trim-sector-ranges-stdin --please-destroy-my-drive "$DISK"
