#!/bin/bash

set -eo pipefail
shopt -s lastpipe

usage() {
	cat >&2 <<EOF
Usage: $0 [<xres>x<yres>] [font]
EOF
	exit 1
}

if (( $# <= 2 )); then
	ARG_RES="$1"
	ARG_FONT="$2"
else
	usage
fi

if ! [[ $ARG_RES ]]; then
	ARG_RES=3840x2160
	ARG_XRES=3840
	ARG_YRES=2160
elif [[ $ARG_RES =~ ^([0-9]+)x([0-9]+)$ ]]; then
	ARG_XRES="${BASH_REMATCH[1]}"
	ARG_YRES="${BASH_REMATCH[2]}"
else
	usage
fi

if ! [[ $ARG_FONT ]]; then
	if (( ARG_XRES > 2560 )); then
		ARG_FONT=ter-v32n
	elif (( ARG_XRES > 1080 )); then
		ARG_FONT=ter-v24n
	else
		ARG_FONT=ter-v16n
	fi
fi

echo "Configuring framebuffer"
parallel --bar fbset -xres "$ARG_XRES" -yres "$ARG_YRES" -vxres "$ARG_XRES" -vyres "$ARG_YRES" -a -fb ::: /dev/fb[0-9]*
echo "Configuring font"
parallel --bar setfont "$ARG_FONT" -C ::: /dev/tty[0-9]*
