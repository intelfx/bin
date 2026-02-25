#!/bin/bash

SCREENSHOT="/tmp/screenshot-$XDG_SESSION_ID-$$.png"

function process() {
	"$@" "${SCREENSHOT}" "${SCREENSHOT}-1" && mv "${SCREENSHOT}-1" "${SCREENSHOT}"
}

function locker() {
	i3lock -i "${SCREENSHOT}"
}

scrot "${SCREENSHOT}"
process env MAGICK_OCL_DEVICE=OFF convert -blur 0x5

if [[ "$XSS_SLEEP_LOCK_FD" ]]; then
	locker {XSS_SLEEP_LOCK_FD}<&-
else
	locker
fi
