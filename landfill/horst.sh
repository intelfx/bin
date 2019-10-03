#!/bin/bash

INTERFACE="${1:-wlan0}"

function bring_back_up() {
	local __r=$?
	trap - ERR EXIT
	sleep 0.5

	echo "-- Restoring"
	systemctl start wpa_supplicant
	nmcli device connect "$INTERFACE"
	exit $__r
}

trap bring_back_up ERR EXIT

echo "-- Preparing"
nmcli device disconnect "$INTERFACE" ||:
systemctl stop wpa_supplicant
ip link set "$INTERFACE" down

sleep 0.5
horst -i "$INTERFACE"
