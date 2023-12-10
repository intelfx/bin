#!/bin/bash

. lib.sh || exit

_usage() {
	echo "Usage: $0 DATA-DIR"
}
declare -A ARGS=(
	[--]=ARG_DIR
)
parse_args ARGS "$@" || usage 
(( ${#ARG_DIR[@]} == 1 )) || usage

DATA_DIR="$ARG_DIR"
[[ -d "$DATA_DIR" ]] || die "Bad source dir: $ARG_DIR"

DATA_DIR="$(realpath --relative-base "$HOME" "$DATA_DIR")"
[[ "$DATA_DIR" != /* ]] || die "Bad source dir (not under $HOME): $ARG_DIR"

DATA_FILE="pts-$(systemd-escape "$DATA_DIR").tar.zst"
[[ ! -e "$DATA_FILE" ]] || die "File '$DATA_FILE' already exists"
[[ -s "$DATA_DIR" ]] || die "Data dir '$DATA_DIR' is empty"

tar -cf "$DATA_FILE" -I 'zstd -T0 -11' "$DATA_DIR"
log "Saved to $DATA_FILE"
find "$DATA_DIR" -mindepth 1 -maxdepth 1 -execdir rm -rf {} \+
log "Cleared $DATA_DIR"
