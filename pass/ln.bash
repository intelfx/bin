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

cmd_ln() {
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
	check_sneaky_paths "$src"
	check_sneaky_paths "$dest"

	local srcpath destpath
	srcpath="$(realpath -q --strip "$PREFIX/$src")"
	destpath="$(realpath -q --strip "$PREFIX/$dest")"
	set_git "$destpath"

	local srcname
	srcname="$(basename "$srcpath")"

	local srcrel destrel
	srcrel="${srcpath#"$PREFIX/"}"
	destrel="${destpath#"$PREFIX/"}"

	if [[ -f "$srcpath.gpg" ]]; then
		if [[ -d "$destpath" ]]; then
			ln -rsf "$srcpath.gpg" -T "$destpath/$srcname.gpg"
			git_add_file "$destpath/$srcname.gpg" "Link $srcrel to $destrel/$srcname."
		else
			ln -rsf "$srcpath.gpg" -T "$destpath.gpg"
			git_add_file "$destpath.gpg" "Link $srcrel to $destrel."
		fi
	elif [[ -d "$srcpath" ]]; then
		if [[ -d "$destpath" ]]; then
			die "Error: cannot link $srcrel to already existng directory $destrel."
		elif [[ -e "$destpath.gpg" ]]; then
			die "Error: cannot link $srcrel to already existing file $destrel."
		else
			ln -rsf "$srcpath" -T "$destpath"
			git_add_file "$destpath" "Link $srcrel to $destrel."
		fi
	else
		die "Error: $srcrel is not in the password store."
	fi
}

cmd_ln "$@"
