#!/bin/bash

. lib.sh || exit 1

STATE_FILE_NEW="$1"
STATE_FILE_OLD="$2"
KEYS=( "${@:3}" )

[[ -f "$STATE_FILE_NEW" ]] || die "Target state file does not exist: '$STATE_FILE_NEW'"
[[ -f "$STATE_FILE_OLD" ]] || die "Target state file does not exist: '$STATE_FILE_OLD'"

tbm900_get_value() {
	local file="$1" key="$2"
	sed -nr "s|^$key = (.*)$|\1|p" "$file" | tail -n1
}

tbm900_set_value() {
	local file="$1" key="$2" value="$3"
	sed -r "s|^($key = ).*$|\1$3|" -i "$file"
}

tbm900_get_runtime() {
	local file="$1"
	sed -nr 's#^(.*/runtime|eng/hobbs) = (.*)$#\2#p' "$file" | sort -g | tail -n1
}

RUNTIME_NEW="$(tbm900_get_runtime "$STATE_FILE_NEW")"
RUNTIME_OLD="$(tbm900_get_runtime "$STATE_FILE_OLD")"

for key in "${KEYS[@]}"; do

	VALUE_OLD="$(tbm900_get_value "$STATE_FILE_OLD" "$key")"

	log "Old state: runtime=$RUNTIME_OLD, $key = $VALUE_OLD"
	VALUE_NEW="$(LC_ALL=C bc <<< "scale=15; $VALUE_OLD * $RUNTIME_NEW / $RUNTIME_OLD" | sed -r 's|^\.|0\.|')"
	log "New state: runtime=$RUNTIME_NEW, $key = $VALUE_NEW"
	tbm900_set_value "$STATE_FILE_NEW" "$key" "$VALUE_NEW"
done
