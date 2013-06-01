#!/bin/bash
DIR=${1:-.}
LAST=~/.moodbar-lastreadsong
C_RET=0

control_c()        # run if user hits control-c
{
  echo "$1" > "$LAST"
  echo "Exiting..."
  exit
}

if [ -e "$LAST" ]; then
  read filetodelete < "$LAST"
  rm "$filetodelete" "$LAST"
fi
exec 9< <(find "$DIR" -type f -regextype posix-awk -iregex '.*\.(mp3|ogg|flac|wma|m4a)') # you may need to add m4a and mp4
while read i
do
  TEMP="${i%.*}.mood"
  OUTF=`echo "$TEMP" | sed 's#\(.*\)/\([^,]*\)#\1/.\2#'`
  trap 'control_c "$OUTF"' INT
  if [ ! -e "$OUTF" ] || [ "$i" -nt "$OUTF" ]; then
    moodbar -o "$OUTF" "$i" || { C_RET=1; echo "An error occurred!" >&2; }
  fi
done <&9
exec 9<&-

exit $C_RET
