#!/bin/bash

# Create new directory structure for mv
for DN in $(find . -type d) 
do
	LCDN=$(echo $DN | tr '[A-Z]' '[a-z]')

	if [ ! -e $LCDN ]; then
		mkdir $LCDN
	fi
done

# Erase old directories
# Move files to the new structure
for DN in $(find . -depth) 
do
	LCDN=$(echo $DN | tr '[A-Z]' '[a-z]')

	if [ -d $DN ] && [ $DN != $LCDN ]; then
		rm -r $DN;
	
	elif [ -f $DN ] && [ ! -e $LCDN ]; then
		mv -i $DN $LCDN
	fi

done
