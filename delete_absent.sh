#!/bin/bash

if [ ! -e "$1/$2" ]; then
	echo $2
	rm $2
fi
