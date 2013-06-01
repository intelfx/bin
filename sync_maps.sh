#!/bin/bash

MAP_FILE="$HOME/sync_list.txt"

function append_new_file() {
	local file fsize extension oldfile

	file="$1"
	fsize=$(stat --printf="%s" "$file")
	extension=${1##*.}
	oldfile="${extensions[${extension}]}"

	if [ -z "$oldfile" ]; then
		extensions[${extension}]="$file"
	else
		local ofsize
		ofsize=$(stat --printf="%s" "$oldfile")

		if [ "$fsize" -gt "$ofsize" ]; then
			extensions[${extension}]="$file"
		fi
	fi
}

while read name; do
	echo "Copying $name"
	name2=$(echo $name | tr ' ' '_')

	unset matching_files
	unset extensions

	declare -a matching_files
	declare -A extensions

	IFS=$'\n';

	for file in $(find . -iname "*$name*" -or -iname "*$name2*"); do
		matching_files+=( "$file" )
	done

	for file in "${matching_files[@]}"; do
		append_new_file "$file"
	done

	for file in ${extensions[@]}; do
		echo "Resulting file: $file"
		cp -v "$file" $2
	done

done < <(cat $MAP_FILE)