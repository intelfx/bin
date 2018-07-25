#!/bin/bash -e

. lib.sh

BT_ID="$1"
HIVE_DIR="$2"


BT_ID=$(echo "$BT_ID" | tr 'a-z' 'A-Z')
if ! [[ "$BT_ID" =~ ^([0-9A-F]{2})(:[0-9A-F]{2}){5}$ ]]; then
	die "Bluetooth device ID '$BT_ID' is invalid"
fi

if ! [[ -d "$HIVE_DIR" ]]; then
	die "Hive directory '$HIVE_DIR' is invalid"
fi

if ! [[ -r "$HIVE_DIR/SYSTEM" ]]; then
	die "Hive file '$HIVE_DIR/SYSTEM' does not exist or is unreadable"
fi

readarray -t BT_PATHES \
	< <(find /var/lib/bluetooth -mindepth 2 -maxdepth 2 -type d -name "$BT_ID")

if (( ${#BT_PATHES[@]} < 1 )); then
	die "No paired devices with id '$BT_ID' found"
fi

trap "rm -f '$reg_file'" EXIT ERR
reg_file="$(mktemp)"

for bt_path in "${BT_PATHES[@]}"; do
	if ! [[ $bt_path =~ ^/var/lib/bluetooth/([^/]+)/([^/]+)$ ]]; then
		die "Internal error: invalid path: '$bt_path'"
	fi
	bt_adapter_id="${BASH_REMATCH[1]}"
	bt_device_id="${BASH_REMATCH[2]}"

	hive_bt_adapter_id="$(echo "$bt_adapter_id" | tr -d ':' | tr 'A-Z' 'a-z')"
	hive_bt_device_id="$(echo "$bt_device_id" | tr -d ':' | tr 'A-Z' 'a-z')"

	reged -x "$HIVE_DIR/SYSTEM" "SYSTEM" "ControlSet001\\Services\\BTHPORT\\Parameters\\Keys\\$hive_bt_adapter_id" "$reg_file"
	bt_key="$(grep -Po "(?<=\"$hive_bt_device_id\"=hex:)([a-f0-9,]+)" "$reg_file" | tr -d ',' | tr 'a-z' 'A-Z')"
	if ! (( ${#bt_key} == 32 )); then
		die "Internal error: invalid key: '${bt_key}'"
	fi

	bt_key_old="$(grep -Po "(?<=Key=)([A-F0-9]+)" "$bt_path/info")"
	if ! (( ${#bt_key_old} == 32 )); then
		die "Internal error: invalid existing key: '${bt_key_old}'"
	fi
	log "Adapter '$bt_adapter_id': device '$bt_device_id': changing key from '$bt_key_old' to '$bt_key'"
	sed -re "s|^Key=.*$|Key=$bt_key|" -i "$bt_path/info"
done
