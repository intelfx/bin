#!/bin/bash

set -e

__libsh="${BASH_SOURCE}.d"
if ! [[ -d "$__libsh" ]]; then
	echo "lib.sh: $__libsh does not exist!"
	return 1
fi

for __libsh_file in "$__libsh"/*.sh; do
	if [[ -x "$__libsh_file" ]]; then
		source "$__libsh_file" || exit
	fi
done

unset __libsh __libsh_file
