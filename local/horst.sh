#!/bin/bash

INTERFACE="${1:-wlan0}"
MONITOR="$INTERFACE-mon"

function bring_back_up() {
	local __r=$?
	iw dev "$MONITOR" del
	systemctl unmask NetworkManager
	systemctl start NetworkManager
	return $__r
}

trap bring_back_up ERR EXIT

systemctl mask NetworkManager
systemctl stop --no-block NetworkManager
systemctl kill NetworkManager
systemctl stop wpa_supplicant
iw dev "$INTERFACE" interface add "$MONITOR" type monitor
rfkill unblock wlan
horst -i "$MONITOR"
