#!/bin/bash

. lib.sh || exit

_usage() {
	echo "Usage: $0 [--fs ARG_FSTYPE] [--mkfs MKFS-OPTIONS] [--mount MOUNT-OPTIONS] DATA-DIR"
}

declare -A ARGS=(
	[--part:]=ARG_PART
	[--fs:]=ARG_FSTYPE
	[--mkfs:]=ARG_MKFS_OPTIONS
	[--mount:]=ARG_MOUNT_OPTIONS
	[--]=ARG_DIR
)
parse_args ARGS "$@" || usage 
(( ${#ARG_DIR[@]} == 1 )) || usage

DATA_DIR="$ARG_DIR"
[[ -d "$DATA_DIR" ]] || die "Bad data dir: $ARG_DIR"

DATA_DIR="$(realpath --relative-base "$HOME" "$DATA_DIR")"
[[ "$DATA_DIR" != /* ]] || die "Bad data dir (not under $HOME): $ARG_DIR"

DATA_FILE="pts-$(systemd-escape "$DATA_DIR").tar.zst"
[[ -e "$DATA_FILE" ]] || die "File '$DATA_FILE' does not exist"

if [[ ${ARG_PART+set} ]]; then
	if mountpoint -q "$DATA_DIR"; then
		sudo umount "$DATA_DIR"
	fi
	sudo mkfs ${ARG_FSTYPE+-t "$ARG_FSTYPE"} ${ARG_MKFS_OPTIONS+$ARG_MKFS_OPTIONS} "$ARG_PART"
	sudo mount "$ARG_PART" ${ARG_MOUNT_OPTIONS+-o "$ARG_MOUNT_OPTIONS"} "$DATA_DIR"
	sudo chown "$(id -u):$(id -g)" "$DATA_DIR"
	log "Re-initialized and mounted $ARG_PART (as $ARG_FSTYPE) on $DATA_DIR"
else
	[[ ! ${ARG_FSTYPE+set} ]] || die "--fstype set without --part"
	[[ ! ${ARG_MKFS_OPTIONS+set} ]] || die "--mkfs set without --part"
	[[ ! ${ARG_MOUNT_OPTIONS+set} ]] || die "--mount set without --part"
	sudo find "$DATA_DIR" -mindepth 1 -maxdepth 1 -execdir rm -rf {} \+
	log "Cleared $DATA_DIR"
fi

tar -xaf "$DATA_FILE"
log "Extracted from $DATA_FILE"
