#!/bin/bash
BASEDIR=~/devel

for extension in gch sdf; do
	echo "Removing *.$extension files"
	find -L $BASEDIR -name "*.$extension" -delete
done
