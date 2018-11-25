#!/bin/bash -e

. lib.sh

BLUEZ_DIR=/var/lib/bluetooth
HIVE_DIR=
BT_ADDR=
BT_IS_BLE=0

function usage() {
	cat >&2 <<EOF

$0 -- copy Bluetooth pairing keys from Windows registry to BlueZ data directory

Usage: $0 [-H,--hive-path HIVE-PATH] [-B,--bluez-path BLUEZ-PATH] [-d,--device DEVICE-ADDR]

-H, --hive-path HIVE-PATH
	Path to Windows hive directory (%WINDIR%/system32/config). Mandatory.

-B, --bluez-path BLUEZ-PATH
	Path to BlueZ data directory. Defaults to $BLUEZ_DIR.

-d, --device DEVICE-ADDR
	Address of a Bluetooth device to operate on (11:22:33:44:55:66). Mandatory.

-l, --le
	Assume this is a BLE device.

EOF
}

opts="$(getopt -o H:B:d:l -l hive-path:,bluez-path:,device:,le -- "$@")"
err=$?
eval set -- "$opts"

while true; do case "$1" in
	-H|--hive-path) HIVE_DIR="$2"; shift 2 ;;
	-B|--bluez-path) BLUEZ_DIR="$2"; shift 2 ;;
	-d|--device-id) BT_ADDR="$2"; shift 2 ;;
	-l|--le) BT_IS_BLE=1; shift ;;
	--) shift; break ;;
esac done

(( $err == 0 && $# == 0 )) || { err "Invalid usage"; usage; exit 1; }

BT_ADDR=$(echo "$BT_ADDR" | tr 'a-z' 'A-Z')
if ! [[ "$BT_ADDR" && "$BT_ADDR" =~ ^([0-9A-F]{2})(:[0-9A-F]{2}){5}$ ]]; then
	err "Invalid Bluetooth device address: \"$BT_ADDR\""
	usage
	exit 1
fi

if ! [[ "$HIVE_DIR" && -d "$HIVE_DIR" ]]; then
	err "Invalid Windows registry hive path: \"$HIVE_DIR\""
	usage
	exit 1
fi

if ! [[ "$BLUEZ_DIR" && -d "$BLUEZ_DIR" ]]; then
	err "Invalid BlueZ data directory path: \"$BLUEZ_DIR\""
	usage
	exit 1
fi

if ! [[ -r "$HIVE_DIR/SYSTEM" ]]; then
	die "Non-existent or unreadable SYSTEM hive file: \"$HIVE_DIR/SYSTEM\""
fi

readarray -t BT_PATHES \
	< <(find "$BLUEZ_DIR" -mindepth 2 -maxdepth 2 -type d -name "$BT_ADDR" -printf '%P\n')

if (( ${#BT_PATHES[@]} < 1 )); then
	die "No devices with address \"$BT_ADDR\" are paired with BlueZ"
fi

trap "rm -f '$reg_file'" EXIT ERR
reg_file="$(mktemp)"

win_to_bluez() {
	reged -x "$HIVE_DIR/SYSTEM" "SYSTEM" "ControlSet001\\Services\\BTHPORT\\Parameters\\Keys\\$hive_bt_ctrl_addr" "$reg_file"

	if ! grep -q "^$hive_bt_dev_addr=hex:" "$reg_file"; then
		cat "$reg_file" >&2
		die "No regular devices with address \"$BT_ADDR\" are paired with Windows. Maybe try -l/--le?"
	fi

	bt_key="$(grep -Po "(?<=\"$hive_bt_dev_addr\"=hex:)([a-f0-9,]+)" "$reg_file" | tr -d ',' | tr 'a-z' 'A-Z')"
	if ! (( ${#bt_key} == 32 )); then
		die "Internal error: invalid key: '${bt_key}'"
	fi

	bt_key_old="$(grep -Po "(?<=Key=)([A-F0-9]+)" "$bt_path/info")"
	if ! (( ${#bt_key_old} == 32 )); then
		die "Internal error: invalid existing key: '${bt_key_old}'"
	fi
	log "Adapter '$bt_ctrl_addr': device '$bt_dev_addr': changing key from '$bt_key_old' to '$bt_key'"
	sed -re "s|^Key=.*$|Key=$bt_key|" -i "$bt_path/info"
}

win_to_bluez_le() {
	reged -x "$HIVE_DIR/SYSTEM" "SYSTEM" "ControlSet001\\Services\\BTHPORT\\Parameters\\Keys\\$hive_bt_ctrl_addr\\$hive_bt_dev_addr" "$reg_file"

	cat "$reg_file" >&2
	die "Not implemented"
}

for bt_path in "${BT_PATHES[@]}"; do
	IFS=/ read bt_ctrl_addr bt_dev_addr <<< "$bt_path"

	hive_bt_ctrl_addr="$(echo "$bt_ctrl_addr" | tr -d ':' | tr 'A-Z' 'a-z')"
	hive_bt_dev_addr="$(echo "$bt_dev_addr" | tr -d ':' | tr 'A-Z' 'a-z')"

	if (( BT_IS_BLE )); then
		win_to_bluez_le
	else
		win_to_bluez
	fi
done
