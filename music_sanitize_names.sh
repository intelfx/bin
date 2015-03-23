#!/bin/bash
shopt -s extglob
while read file; do
	file_new="$(sed -re "s|\.*(\.[^\. ]+)?$|\1|" <<< "$file")"
	if [[ "$file_new" != "$file" ]]; then
#		echo "'$file' -> '$file_new'"
		if [[ -e "$file_new" ]]; then
			echo "CONFLICT: '$file' -> already existing '$file_new'"
		else
			mv -v "$file" "$file_new"
		fi
	fi
done < <(find . -mindepth 1 -depth)
