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

SUBNET_BITS="$1"
SUBNET_IP_BYTES=()

if (( SUBNET_BITS < 0 || SUBNET_BITS > 32 )); then
	die "E: wrong subnet: /$SUBNET_BITS"
fi

while (( SUBNET_BITS >= 8 )); do
	(( SUBNET_BITS -= 8 ))
	SUBNET_IP_BYTES+=( 255 )
done

if (( SUBNET_BITS )); then
	SUBNET_IP_BYTES+=( $(( 0xFF & ~((1 << (8-SUBNET_BITS)) - 1) )) )
fi

while (( ${#SUBNET_IP_BYTES[@]} < 4 )); do
	SUBNET_IP_BYTES+=( 0 )
done

(
IFS=.
echo "${SUBNET_IP_BYTES[*]}"
)
