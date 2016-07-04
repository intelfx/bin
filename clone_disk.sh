#!/bin/bash

set -e

SRC="$1"
DEST="$2"

function blk_size() {
	echo $(( $(blockdev --getsz "$1") * 512 ))
}

function file_size() {
	if [[ -f "$1" ]]; then
		stat -c "%s" "$1"
	else
		echo 0
	fi
}

if [[ -b "$SRC" ]]; then
	SRC_IS_BLK=1
	SRC_SIZE=$(blk_size "$SRC")
else
	SRC_SIZE=$(file_size "$SRC")
fi

if [[ -b "$DEST" ]]; then
	DEST_IS_BLK=1
	DEST_SIZE=$(blk_size "$DEST")
else
	DEST_SIZE=$(file_size "$DEST" || echo 0)
fi

function cleanup() {
	echo ":: detach loop devices..."

	if (( SRC_IS_BLK )); then
		echo "   -> not detaching block device $SRC_LOOP"
	else
		echo "   -> $SRC_LOOP for src"
		losetup -d "$SRC_LOOP"
	fi

	if (( DEST_IS_BLK )); then
		echo "   -> not detaching block device $DEST_LOOP"
	else
		echo "   -> $DEST_LOOP for dest"
		losetup -d "$DEST_LOOP"
	fi
	
}

function cleanup_err() {
	echo ":: remove incomplete destination file"
	if (( DEST_IS_BLK )); then
		echo "   -> not removing block device $DEST"
	else
		rm -f "$DEST"
	fi
}

trap cleanup EXIT
trap cleanup_err ERR

echo ":: truncate '$DEST' to size of '$SRC'"
if (( DEST_IS_BLK )); then
	if (( DEST_SIZE >= SRC_SIZE )); then
		echo "   -> not truncating block device $DEST of size $DEST_SIZE >= $SRC_SIZE"
	else
		echo "   -> block device $DEST is of size $DEST_SIZE < $SRC_SIZE, cannot proceed"
	fi
else
	rm -f "$DEST"
	truncate --size "$SRC_SIZE" "$DEST"
fi
echo

echo ":: copy partition table"
blkid "$SRC"
SRC_PTTYPE="$(blkid -s PTTYPE -o value "$SRC")"
case "$SRC_PTTYPE" in
dos)
	echo "   -> MBR detected -- using sfdisk"
	sfdisk -d "$SRC" | sfdisk "$DEST"
	;;
gpt)
	echo "   -> GPT detected -- using sgdisk"
	TEMPFILE="$(mktemp)"
	sgdisk -b "$TEMPFILE" "$SRC"
	sgdisk -l "$TEMPFILE" "$DEST"
	rm -f "$TEMPFILE"
	;;
*)
	echo "   -> unknown partition table type '$SRC_PTTYPE'!"
	false
	;;
esac
echo

echo ":: setup loop devices..."
if (( SRC_IS_BLK )); then
	SRC_LOOP="$SRC"
	SRC_LOOP_PART_PREFIX="$SRC"
	echo "   -> skipping loopback for block device $SRC"
else
	SRC_LOOP=$(losetup -Pf --show "$SRC")
	SRC_LOOP_PART_PREFIX="${SRC_LOOP}p"
	echo "   -> '$SRC_LOOP' for '$SRC'"
fi

if (( DEST_IS_BLK )); then
	DEST_LOOP="$DEST"
	DEST_LOOP_PART_PREFIX="$DEST"
	echo "   -> skipping loopback for block device $DEST"
else
	DEST_LOOP=$(losetup -Pf --show "$DEST")
	DEST_LOOP_PART_PREFIX="${DEST_LOOP}p"
	echo "   -> '$DEST_LOOP' for '$DEST'"
fi
echo

echo ":: clone partitions..."
for src_part in "$SRC_LOOP_PART_PREFIX"?*; do
	partnr="${src_part#$SRC_LOOP_PART_PREFIX}"
	dest_part="$DEST_LOOP_PART_PREFIX$partnr"

	part_type="$(blkid "$src_part" -o value -s TYPE)"
	echo -n "   -> '$src_part' "

	if [[ "$part_type" ]]; then
		echo -n "of type '$part_type' "
	fi

	echo -n "- "

	if [[ "$part_type" ]] && type -t partclone.$part_type &>/dev/null; then
		echo "using 'partclone.$part_type'"
		"partclone.$part_type" -b -s "$src_part" -O "$dest_part"
	elif [[ "$part_type" == "swap" ]]; then
		echo "recreating swapspace label '$(blkid "$src_part" -o value -s LABEL)' uuid '$(blkid "$src_part" -o value -s UUID)'"
		mkswap \
			-L "$(blkid "$src_part" -o value -s LABEL)" \
			-U "$(blkid "$src_part" -o value -s UUID)" \
			"$dest_part"
	else
		echo "using partclone.dd"
		partclone.dd -s "$src_part" -O "$dest_part"
	fi

	echo
done
