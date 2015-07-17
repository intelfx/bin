#!/bin/bash

set -e

SRC="$1"
DEST="$2"

function cleanup() {
	echo ":: detach loop devices..."

	if [[ -e "$SRC_LOOP" ]]; then
		echo "   -> $SRC_LOOP for src"
		losetup -d "$SRC_LOOP"
	fi

	if [[ -e "$DEST_LOOP" ]]; then
		echo "   -> $DEST_LOOP for dest"
		losetup -d "$DEST_LOOP"
	fi
}

function cleanup_err() {
	echo ":: remove incomplete destination file"
	rm -f "$DEST"
}

trap cleanup EXIT
trap cleanup_err ERR

echo ":: truncate '$DEST' to size of '$SRC'"
rm -f "$DEST"
truncate --reference "$SRC" "$DEST"
echo

echo ":: copy partition table using sfdisk"
sfdisk -d "$SRC" | sfdisk "$DEST"
echo

echo ":: setup loop devices..."
SRC_LOOP=$(losetup -Pf --show "$SRC")
echo "   -> '$SRC_LOOP' for '$SRC'"
DEST_LOOP=$(losetup -Pf --show "$DEST")
echo "   -> '$DEST_LOOP' for '$DEST'"
echo


echo ":: clone partitions..."
for src_part in "$SRC_LOOP"p*; do
	dest_part="${src_part/$SRC_LOOP/$DEST_LOOP}"

	part_type="$(blkid "$src_part" -o value -s TYPE)"
	if [[ "$part_type" ]]; then
		echo -n "   -> '$src_part' of type '$part_type' - "

		if type -t partclone.$part_type &>/dev/null; then
			echo "using 'partclone.$part_type'"
			"partclone.$part_type" -b -s "$src_part" -o "$dest_part"
		else
			echo "using partclone.dd"
			partclone.dd -s "$src_part" -o "$dest_part"
		fi

		echo
	fi
done
