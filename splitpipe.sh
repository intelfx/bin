#!/bin/bash

function log() {
	echo "$*" >&2
}

function die() {
	log "$*"
	exit 1
}

function main_to() {
	# data on stdin
	local PIECE_NR="1"
	while :; do
		local TEMP_FILE="$(mktemp -p "$TMPDIR")"
		local RETRY_NR=1
		trap "rm -f '$TEMP_FILE'" RETURN EXIT
		log ":: Piece $PIECE_NR, retry $RETRY_NR via tee."
		eval "$(printf "$COMMAND_SERIALIZED" "$PIECE_NR")"
		head -c "$SIZE" | tee --output-error=warn "$TEMP_FILE" | "${COMMAND[@]}" || {
			# the command had failed
			while :; do
				(( ++RETRY_NR ))
				log ":: Piece $PIECE_NR, retry $RETRY_NR."
				"${COMMAND[@]}" < "$TEMP_FILE" && {
					break
				}
			done
		}

		if [[ ! -s "$TEMP_FILE" ]]; then
			log ":: Piece of zero size, exiting with total of $PIECE_NR pieces of which last is empty."
			return
		fi

		rm -f "$TEMP_FILE"
		trap - RETURN EXIT
		(( ++PIECE_NR ))
	done
}

function main_from() {
	local PIECE_NR="1"
	set -o pipefail
	while :; do
		local TEMP_FILE="$(mktemp -p "$TMPDIR")"
		local RETRY_NR=1
		trap "rm -f '$TEMP_FILE'" RETURN EXIT
		log ":: Piece $PIECE_NR, retry $RETRY_NR via tee."
		eval "$(printf "$COMMAND_SERIALIZED" "$PIECE_NR")"
		"${COMMAND[@]}" | tee "$TEMP_FILE" || {
			# the command had failed
			while :; do
				(( ++RETRY_NR ))
				CURRENT_SIZE="$(stat --printf='%s' "$TEMP_FILE")"
				log ":: Piece $PIECE_NR, retry $RETRY_NR (already downloaded $CURRENT_SIZE bytes)."
				# this is suboptimal: we download but deliberately throw away first $CURRENT_SIZE bytes
				"${COMMAND[@]}" | tail -c +$(( CURRENT_SIZE + 1 )) | tee -a "$TEMP_FILE" && {
					break
				}
			done
		}

		[[ -s "$TEMP_FILE" ]] || {
			log ":: Piece of zero size, exiting with total of $PIECE_NR pieces of which last is empty."
			return
		}

		rm -f "$TEMP_FILE"
		trap - RETURN EXIT
		(( ++PIECE_NR ))
	done
}

set -e

ARGS="$(getopt --long "to,from,size:,tempdir:" -o "tfs:d:" -- "$@")"
eval set -- "$ARGS"

SIZE="1K"
TMPDIR="/tmp"
PATTERN="{}"

while (( $# )); do
	case "$1" in
	-t|--to)
		MODE=to
		;;
	-f|--from)
		MODE=from
		;;
	-s|--size)
		shift
		SIZE="$1"
		;;
	-d|--tempdir)
		shift
		TMPDIR="$1"
		;;
	--)
		shift
		break
		;;
	*)
		die "E: Invalid option: '$1'"
		;;
	esac
	shift
done

COMMAND=( "$@" )

log "N: using piece size $SIZE."
log "N: using temporary directory $TMPDIR to store at most one piece."
log "N: using command $(printf "'%s' " "${COMMAND[@]}"), piece id pattern is '$PATTERN'."
log "N: piping $MODE command."

COMMAND_SERIALIZED="$(declare -p COMMAND | sed -r -e 's|\{\}|%d|' -e 's|\{([0-9]+)\}|%0\1d|')"
eval "$COMMAND_SERIALIZED"
log "N: printf-ized command is $(printf "'%s' " "${COMMAND[@]}")"

case "$MODE" in
to)
	main_to "$@"
	;;
from)
	main_from "$@"
	;;
*)
	die "E: Invalid mode: '$MODE'"
	;;
esac
