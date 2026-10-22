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

usage() {
	if (( $# )); then
		printf "E: %s\n" "$*"
	fi
	cat <<EOF
Usage: $PROGRAM $COMMAND [-1|--first|--password] [-F|--field field-name[,...]] pass-name...

If neither -1 nor -F are specified, -1 is the implied default.
EOF
	exit 1
}

cmd_get() {
	local opts fields=() password clipboard
	opts="$($GETOPT -o '1F:c' -l first,password,field: -n "$PROGRAM-get" -- "$@")"
	local err=$?
	eval set -- "$opts"
	while true; do case $1 in
		-c)
			clipboard=1
			shift ;;
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

	(( ! $err )) || usage
	(( $# )) || usage "expected at least 1 positional argument"

	if ! [[ ${password+set} || ${fields+set} ]]; then
		password=1
	fi

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

	if ! (( ${#output[@]} )); then
		return
	fi


	if (( clipboard )); then
		if (( ${#output[@]} == 1 )); then
			clip "${output[0]}" "$1"
		else
			local text
			printf -v text '%s\n' "${output[@]}"
			local name="(${#output[@]} lines)"
			clip "$text" "$name"
		fi
	else
		printf '%s\n' "${output[@]}"
	fi

}

cmd_get "$@"
