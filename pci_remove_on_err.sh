#!/bin/bash

source "${BASH_SOURCE##*/}/framework/src/framework" || exit

ID="$1"

check "[[ '$ID' ]]" \
	"No PCI ID to watch specified"

while :; do
	journalctl -t kernel -p err -f -n0 | grep -q "$ID"

	report_try "$(date): error message caught, removing $(i_e "$ID")"
	"${BASH_SOURCE##*/}/pci_remove.sh" "$ID"
	report
done
