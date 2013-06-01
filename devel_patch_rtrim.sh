#!/bin/bash
for file in $@; do
	echo ">> Fixing $file"
	sed -re "s|^(\+.*)[[:space:]]+$|\1|g" -i $file
done
