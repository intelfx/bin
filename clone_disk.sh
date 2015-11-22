#!/bin/bash

set -e

SRC="$1"
DEST="$2"

if [[ -b "$SRC" ]]; then
	SRC_IS_BLK=1
fi

if [[ -b "$DEST" ]]; then
	DEST_IS_BLK=1
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
if ! (( DEST_IS_BLK )); then
	rm -f "$DEST"
	if (( SRC_IS_BLK )); then
		truncate --size $(( $(blockdev --getsz "$SRC") * 512 )) "$DEST"
	else
		truncate --reference "$SRC" "$DEST"
	fi
else
	echo "   -> not truncating block device $DEST"
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
	SRC_LOOP=$(losetup -Pf --show "$SRC")
	SRC_LOOP_PART_PREFIX="${SRC_LOOP}p"
	echo "   -> '$SRC_LOOP' for '$SRC'"
else
	SRC_LOOP="$SRC"
	SRC_LOOP_PART_PREFIX="$SRC"
	echo "   -> skipping loopback for block device $SRC"
fi

if (( DEST_IS_BLK )); then
	DEST_LOOP=$(losetup -Pf --show "$DEST")
	DEST_LOOP_PART_PREFIX="${DEST_LOOP}p"
	echo "   -> '$DEST_LOOP' for '$DEST'"
else
	DEST_LOOP="$DEST"
	DEST_LOOP_PART_PREFIX="$DEST"
	echo "   -> skipping loopback for block device $DEST"
fi
echo

echo ":: clone partitions..."
for src_part in "$SRC_LOOP_PART_PREFIX"*; do
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
	else
		echo "using partclone.dd"
		partclone.dd -s "$src_part" -O "$dest_part"
	fi

	echo
done
