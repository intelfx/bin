#!/bin/bash

xrdb -E "$@" | sed -nre 's|^\*color([0-9]*):.*#(.*)$|\1 \2|p' | while read n color; do
	echo $'\033]P'"$(printf '%X' "$n")$color"
done

clear
