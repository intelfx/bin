#!/bin/bash

FILE="$1"
[ -n "$FILE" ] || { echo "No file given!" >&2; exit 1; }

TIME_EXIF="$(LC_ALL=C exiv2 pr "$FILE" | grep -a timestamp | sed -e 's|Image timestamp : ||g')"
DATE=$(echo $TIME_EXIF | cut -d' ' -f1)
TIME=$(echo $TIME_EXIF | cut -d' ' -f2)

YYYY=$(echo $DATE | cut -d':' -f1)
YY=${YYYY:2}
MM=$(echo $DATE | cut -d':' -f2)
DD=$(echo $DATE | cut -d':' -f3)

hh=$(echo $TIME | cut -d':' -f1)
mm=$(echo $TIME | cut -d':' -f2)
ss=$(echo $TIME | cut -d':' -f3)


echo ">> File: $FILE"

if [ -n "$DEBUG" ]; then
	echo "    - exif: $EXIF_TIME"
	echo "    - date: $DATE"
	echo "    - time: $TIME"
	echo "    - year: $YYYY ($YY)"
	echo "    - month: $MM"
	echo "    - day: $DD"
	echo "    - hours: $hh"
	echo "    - minutes: $mm"
	echo "    - seconds: $ss"
fi
touch -t ${YYYY}${MM}${DD}${hh}${mm}.${ss} -m "$FILE"

