#!/bin/bash

shopt -s nullglob

for file in $HOME/devel/cmake/*.cmake; do
	echo ">> Processing $file:"
	find $HOME/devel/__* $HOME/parallels -name "$(basename $file)" -exec cp -lvf $file {} \;
done
