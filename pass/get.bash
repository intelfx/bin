#!/bin/bash
# pass get - Password Store Extension (https://www.passwordstore.org/)
# Copyright (C) 2024 Ivan Shapovalov <intelfx@intelfx.name>
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

set -eo pipefail
shopt -s lastpipe

cmd_get() {
	local opts fields=() password
	opts="$($GETOPT -o '1,F:' -l first,password,field: -n "$PROGRAM" -- "$@")"
	local err=$?
	eval set -- "$opts"
	while true; do case $1 in
		-1|--first|--password)
			password=1
			shift ;;
		-F|--field)
			local fs
			IFS=, read -ra fs <<<"$2"
			fields+=( "${fs[@]}" )
			shift 2 ;;
		--) shift; break ;;
	esac done

	[[ $err -ne 0 || $# -lt 1 ]] && die "Usage: $PROGRAM $COMMAND [-1|--first|--password] [--field field-name[,...]] pass-name..."

	local f
	local line k v
	local -a lines output

	declare -A fields_set fields_found
	for k in "${fields[@]}"; do
		fields_set["$k"]=1
	done

	for f; do
		cmd_show "${target[@]}" "$f" | readarray -t lines
		fields_found=()

		if (( password )); then
			if (( ${#lines[*]} < 1 )); then
				die "$f: empty"
			fi
			output+=( "${lines[0]}" )
		fi
		for line in "${lines[@]:1}"; do
			if [[ $line =~ ^([^ ]+)[[:space:]]*:[[:space:]]*([^ ]*)$ ]]; then
				k="${BASH_REMATCH[1]}"
				v="${BASH_REMATCH[2]}"
				if [[ ${fields_set["$k"]+set} ]]; then
					fields_found["$k"]=1
					output+=( "$v" )
				fi
			fi
		done

		if (( ${#fields_found[*]} != ${#fields_set[*]} )); then
			die "$f: not all requested fields present"
		fi
	done

	if (( ${#output[@]} )); then
		printf '%s\n' "${output[@]}"
	fi
}

cmd_get "$@"
