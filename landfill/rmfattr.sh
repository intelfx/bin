#!/bin/bash -e

set -eo pipefail
shopt -s lastpipe

pattern="$1"
shift

for file; do
	getfattr "$file" | readarray -t attrs
	for a in "${attrs[@]}"; do
		if [[ "$a" =~ $pattern ]]; then
			setfattr -x "$a" "$file"
		fi
	done
done
