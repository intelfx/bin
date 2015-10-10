#!/bin/bash

for ((oops_id=1;; ++oops_id)); do
	oops_string="Oops#${oops_id}"
	oops_output="oops_${oops_id}.txt"
	oops_names=()

	readarray -t oops_names < <(grep -l "$oops_string" -R /sys/fs/pstore)

	printf "%s\n" "${oops_names[@]}" | sort -r | xargs -r cat | grep -v "^$oops_string" > "$oops_output"
	if [[ ! -s "$oops_output" ]]; then
		rm -f "$oops_output"
		break
	fi

	echo ":: extracted oops $oops_id, removing files"
	rm -f "${oops_names[@]}"
done
