#!/bin/bash
cd /sys/class/scsi_host

while :; do
	clear
	for host in /sys/class/scsi_host/host*; do
		if [[ ! -e "$host" ]]; then continue; fi

		echo -n "${host##*/}:"
		for file in $host/ahci_alpm_*; do
			if [[ ! -e "$file" ]]; then continue; fi

			printf " [${file##*/}: %10s" "$(< $file)]"
		done
		echo ""
	done
	sleep 0.5
done
