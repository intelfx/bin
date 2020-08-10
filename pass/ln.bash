#!/bin/bash
# pass ln - Password Store Extension (https://www.passwordstore.org/)
# Copyright (C) 2020 Ivan Shapovalov <intelfx@intelfx.name>
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
	opts="$($GETOPT -o s -l symbolic -n "$PROGRAM" -- "$@")"
	local err=$?
	eval set -- "$opts"
	while true; do case $1 in
		# no-op -- all links are symbolic, accepted for convenience
		-s|--symbolic) shift ;;
		--) shift; break ;;
	esac done

	[[ $err -ne 0 || $# -ne 2 ]] && die "Usage: $PROGRAM $COMMAND [-s|--symbolic] src dest"

	local src="$1" dest="$2"

	git

	local f passfile

	for f; do
		passfile="$PREFIX/$f.gpg"

		[[ -f $passfile ]] || continue

		cmd_show "${target[@]}" "$f"
		break
	done
}

cmd_ln "$@"
