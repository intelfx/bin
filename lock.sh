#!/bin/bash

SCREENSHOT="/tmp/screenshot-$XDG_SESSION_ID-$$.png"

function process() {
	"$@" "${SCREENSHOT}" "${SCREENSHOT}-1" && mv "${SCREENSHOT}-1" "${SCREENSHOT}"
}

scrot "${SCREENSHOT}"
process convert -blur 0x5
i3lock -i "${SCREENSHOT}"
