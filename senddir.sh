#!/bin/bash

(( $# )) || { echo "== No arguments. Need: <host>[:<path>] <options to archive.sh>" >&2; exit 1; }

IFS=: read HOSTSPEC DESTPATH <<< "$1"
shift

if (( $# == 1 )) && [[ -f "$1" ]]; then
	echo "-- Sending file \"$1\" as-is"
	SENT_FILE="$1"
else
	echo "-- Compressing"
	archive.sh "$@" -D /tmp -N "senddir-$$" || { echo "== Archiver failed." >&2; exit 1; }
	SENT_FILE="$(ls /tmp/senddir-$$*)"
fi

[ -f "$SENT_FILE" ] || { echo "== Invalid file to send: $SENT_FILE." >&2; exit 1; }
echo "-- Sending"
scp "$SENT_FILE" $HOSTSPEC:/tmp

[[ "$DESTPATH" ]] || DESTPATH="$(pwd)"

cat <<- EOF | ssh "$HOSTSPEC"
	mkdir -p "$DESTPATH"
	cd "$DESTPATH"
	rm -rf * .*
	tar -xf "/tmp/$(basename "$SENT_FILE")"
	rm "/tmp/$(basename "$SENT_FILE")"
	EOF
