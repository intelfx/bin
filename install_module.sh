#!/bin/bash

SRC="$1"
if ! [[ -f "$SRC" ]]; then
   echo "== Wrong file '$SRC'" >&2
   exit 1
fi

SRCNAME="${SRC##*/}"

echo "-- Name '$SRCNAME'"

DEST="/lib/modules/$(uname -r)/kernel/${SRC%/*}"

echo "-- Dest '$DEST'"

rm -vf "${DEST}/${SRCNAME}"*
install -vm644 "${SRC}" "${DEST}/${SRCNAME}"
depmod -a
