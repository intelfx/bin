#!/bin/bash

. lib.sh || exit

FILE="$1"
if ! [[ -w "$FILE" ]]; then
	die "'$FILE' is not writable"
fi

eval "$(globaltraps)"

PTTYPE="$(blkid -o value -s PTTYPE "$FILE")"
TYPE="$(blkid -o value -s TYPE "$FILE")"
if [[ "$PTTYPE" ]]; then
	LOOP_FILE="$(losetup -Pf --show "$FILE")"
	ltrap "losetup -d '$LOOP_FILE'"
	log "Set up whole-disk loopback device at '$LOOP_FILE'"
	ls "$LOOP_FILE"*
	find "$LOOP_FILE"p[0-9]* | readarray -t PART_FILES
	log "Discovered ${#PART_FILES[@]} partitions"
elif [[ "$TYPE" ]]; then
	LOOP_FILE="$(losetup -f --show "$FILE")"
	ltrap "losetup -d '$LOOP_FILE'"
	log "Set up whole-partition loopback device at '$LOOP_FILE'"
	PART_FILES=( "$LOOP_FILE" )
else
	err "$FILE: could not find a partition or a partition table signature, exiting"
fi

WORK_DIR="$(mktemp -d)"

for f in "${PART_FILES[@]}"; do
	TYPE="$(blkid -o value -s TYPE "$f")"
	if ! [[ "$TYPE" ]]; then
		warn "$f: could not find a partition signature, skipping"
		continue
	fi

	MOUNT_DIR="$WORK_DIR/${f##*/}"
	mkdir -p "$MOUNT_DIR"
	ltrap "umount -l '$MOUNT_DIR'"
	if ! mount "$f" "$MOUNT_DIR" -o discard; then
		err "$f: could not mount at $MOUNT_DIR, skipping"
		continue
	fi
	if ! fstrim -v "$MOUNT_DIR"; then
		err "$f: could not run fstrim at $MOUNT_DIR"
	fi
	sync
	if ! { umount "$MOUNT_DIR" || umount -l "$MOUNT_DIR"; }; then
		err "$f: could not umount at $DIR, exiting"
		luntrap
		exit 1
	fi
	luntrap
done
sync
