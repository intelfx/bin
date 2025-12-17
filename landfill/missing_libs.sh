#!/bin/bash

set -eo pipefail
shopt -s lastpipe
. lib.sh


# broken: `scanelf --use-ldpath` does not use rpath/runpath, leading to false positives
# | sudo parallel -X "scanelf -b --use-ldpath -F $'%F\t%n'" | rg '^([^\t]+)\t(.+,)*([^/]+)[,$]'

process_files() {
	set -eo pipefail
	shopt -s lastpipe

	for file; do
		if ! result="$(ldd "$file" 2>&1)"; then
			printf "%s: ERROR\n%s\n" "$file" "$result"
			continue
		fi
		if [[ $result == *"=> not found"* ]]; then
			printf "%s\n" "$file"
			grep "not found" <<<"$result"
		fi
	done
}
export -f process_files

pacman -Qql \
	| grep -vE '/$' \
	| parallel -X "bfs {} -type f -executable" \
	| parallel -X "scanelf -b -E ET_DYN -F $'%F\t%a'" \
	| awk -F '\t' '$2 == "EM_X86_64" { print $1 }' \
	| parallel -X "process_files"

