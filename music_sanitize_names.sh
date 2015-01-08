#!/bin/bash
shopt -s extglob
while read file; do
	file_new="$(sed -re "s|\.*(\.[^\. ]+)?$|\1|" <<< "$file")"
	if [[ "$file_new" != "$file" ]]; then
		mv -v "$file" "$file_new"
	fi
done < <(find . -mindepth 1 -depth)
