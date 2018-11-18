#!/bin/bash
# pass either - Password Store Extension (https://www.passwordstore.org/)
# Copyright (C) 2018 Ivan Shapovalov <intelfx@intelfx.name>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
# []

VERSION="0.1.0"

cmd_either_show() {
	local opts target=()
	opts="$($GETOPT -o c::q:: -l clip::,qrcode:: -n "$PROGRAM" -- "$@")"
	local err=$?
	eval set -- "$opts"
	while true; do case $1 in
		-c|--clip) target+=( "$1" "$2" ); shift 2 ;;
		-q|--qrcode) target+=( "$1" "$2" ); shift 2 ;;
		--) shift; break ;;
	esac done

	[[ $err -ne 0 || $# -lt 1 ]] && die "Usage: $PROGRAM $COMMAND [--clip[=line-number],-c[line-number]] [--qrcode[=line-number],-q[line-number]] pass-name..."

	local f passfile

	for f; do
		passfile="$PREFIX/$f.gpg"

		[[ -f $passfile ]] || continue

		cmd_show "${target[@]}" "$f"
		break
	done
}

cmd_either_show "$@"
