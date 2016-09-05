#!/bin/bash

source "${BASH_SOURCE##*/}/framework/src/framework" || exit

PCI_ID="$1"

check "[[ '$PCI_ID' ]]" \
	die "PCI ID not specified"

PCI_DIR="/sys/bus/pci/devices/$PCI_ID"

check "[[ -d '$PCI_DIR' ]]" \
	"PCI ID $(i_e "$PCI_ID") is invalid"

report_try "Re-plugging $(i_n "$PCI_ID")"

report_status reset
echo 1 > "$PCI_DIR/reset"

report_status disable
echo 0 > "$PCI_DIR/enable"

report_status remove
echo 1 > "$PCI_DIR/remove"

report_status "rescan PCI bus"
echo 1 > "/sys/bus/pci/rescan"

report_status "re-enable"
echo 1 > "$PCI_DIR/enable"

report_done
