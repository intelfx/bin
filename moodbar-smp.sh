#!/bin/bash
NUMCPU="$(grep ^processor /proc/cpuinfo | wc -l)"

find . -type f -regextype posix-awk -iregex '.*\.(mp3|ogg|flac|wma|m4a)' | while read i ; do

       while [ `jobs -p | wc -l` -ge $NUMCPU ] ; do
               sleep 1
       done

       TEMP="${i%.*}.mood"
       OUTF=`echo "$TEMP" | sed 's#\(.*\)/\([^,]*\)#\1/.\2#'`
       moodbar -o "$OUTF" "$i" &
done
