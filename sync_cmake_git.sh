#!/bin/bash

shopt -s nullglob

for file in $HOME/devel/cmake/*.cmake; do
	echo ">> Processing $file:"
	find . -name $(basename $file) -exec cp -flv $file {} \; -exec git add {} \;
done

git commit -m "Updated CMake templates."
