#!/bin/bash

SVG_PATH="/tmp/systemd-analyze.svg"
MAIN_UNIT="lightdm.service"

case "$1" in
	critical-chain)
		exec systemd-analyze critical-chain "$MAIN_UNIT"
		;;
	plot)
		systemd-analyze plot > "$SVG_PATH" || exit 1
		exec konqueror "$SVG_PATH"
		;;
	*)
		exit 1
esac
