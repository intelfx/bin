#!/bin/bash

function log() {
        echo "$*" >&2
}

function die() {
        log "$*"
	exit 1
}

if (( $# != 1 )); then
	die "E: this program expects one argument."
fi

MAC_ADDR="$1"
readarray -t MAC_BYTES <<< "${MAC_ADDR//:/$'\n'}"

if (( ${#MAC_BYTES[@]} != 6 )); then
	die "E: malformed MAC address: '$MAC_ADDR'."
fi

IP_BYTES=(10 0 0 0)

for (( i=0; i<6; i+=2 )); do
	(( IP_BYTES[1] ^= 0x${MAC_BYTES[i]} )) ||:
done

for (( i=1; i<6; i+=2 )); do
	(( IP_BYTES[2] ^= 0x${MAC_BYTES[i]} )) ||:
done

( IFS="."; echo "${IP_BYTES[*]}" )
