#!/bin/bash

COMBINEFILE=".combine-$$.ps"
declare -a INPUTFILES

cleanup() {
	rm -f "$COMBINEFILE"
	rm -f "${INPUTFILES[@]}"
}

set -e
trap "cleanup" EXIT TERM HUP INT

for arg; do
	PROCESSED=".input-$$-${arg##*/}"
	INPUTFILES+=("$PROCESSED")
	ps2ps "$arg" "$PROCESSED"
done

cat > "$COMBINEFILE" <<"EOF"
%!PS-Adobe-3.0
/Oldshowpage /showpage load def
/showpage {} def
EOF

for file in "${INPUTFILES[@]}"; do

#	read x0 y0 x1 y1 <<< "$(sed -nre 's|%%BoundingBox: ([0-9 ]*)|\1|p' < "$file")"
#	echo "File '$file' bounding box x0=$x0 y0=$y0 x1=$x1 y1=$y1"

#	cat <<-EOF
#		($file) run
#		1 1 scale
#		0 0 moveto
#		0 $(( y1 + 10 )) translate
#	EOF

	cat >> "$COMBINEFILE" <<-EOF
		($file) run
	EOF
done

cat >> "$COMBINEFILE" <<"EOF"
Oldshowpage
EOF

ps2ps -dNOSAFER "$COMBINEFILE" "out.ps"
