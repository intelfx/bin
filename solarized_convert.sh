#!/bin/bash

declare -a SOLARIZED_COLORS=(
	# base03
	"00 2b 36"
	# base02
	"07 36 42"
	# base01
	"58 6e 75"
	# base00
	"65 7b 83"
	# base0
	"83 94 96"
	# base1
	"93 a1 a1"
	# base2
	"ee e8 d5"
	# base3
	"fd f6 e3"
)

function gen_color_hex() {
	read r g b <<< "$1"
	echo "$r$g$b"
}

function gen_color_dec() {
	read r g b <<< "$1"
	echo "$(( 0x$r )),$(( 0x$g )),$(( 0x$b ))"
}

function gen_sed_command_stage1() {
	echo -n "sed "

	for type in hex dec; do
		for (( i=0; i < 8; ++i )); do
			SRC="$(gen_color_${type} "${SOLARIZED_COLORS[$i]}")"
			DEST="__solarized_color_${i}_${type}_"
			echo -n "-e \"s/$SRC/$DEST/g\" "
		done
	done

	echo -n "-e \"s/Dark/__solarized_dark__/g\" "
	echo -n "-e \"s/Light/__solarized_light__/g\" "

	echo "\"$1\""
}

function gen_sed_command_stage2() {
	echo -n "sed "

	for type in hex dec; do
		for (( i=0; i < 8; ++i )); do
			SRC="__solarized_color_${i}_${type}_"
			DEST="$(gen_color_${type} "${SOLARIZED_COLORS[$((7-i))]}")"
			echo -n "-e \"s/$SRC/$DEST/g\" "
		done
	done

	echo -n "-e \"s/__solarized_dark__/Light/g\" "
	echo -n "-e \"s/__solarized_light__/Dark/g\" "
}

eval $(gen_sed_command_stage1 "$1") | eval $(gen_sed_command_stage2)
