#!/bin/bash

set -e

SVG_PATH="/tmp/systemd-analyze.svg"
MAIN_UNIT="gdm.service"
#SVG_APP="xdg-open"
SVG_APP="firefox"

ACTION="$1"
shift

case "$ACTION" in
	critical-chain)
		if (( $# )); then
			MAIN_UNIT="$1"
			shift
		fi
		exec systemd-analyze critical-chain "$MAIN_UNIT" "$@"
		;;
	plot)
		systemd-analyze plot "$@" > "$SVG_PATH"
		exec "${SVG_APP[@]}" "$SVG_PATH"
		;;
	dot)
		systemd-analyze dot "$@" | dot -Tsvg > "$SVG_PATH"
		exec "${SVG_APP[@]}" "$SVG_PATH"
		;;
	*)
		exit 1
esac
