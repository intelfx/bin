#!/bin/bash
for file in "$1"/*; do
	F=$(echo "$(basename "$file")" | sed -re "s/(.*) [[:digit:]]*\..*/\1/")
	mkdir -p "$F"
	mv "$file" "$F"
done
