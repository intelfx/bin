#!/bin/bash

. lib.sh || exit 1

XPLANE_ROOT="/mnt/c/Games/Steam/steamapps/common/X-Plane 11"

XPLANE_PLUGINS="$XPLANE_ROOT/Resources/plugins"
XPLANE_PLUGINS_QUARANTINE="$XPLANE_ROOT/Resources/plugins.quarantine"
XPLANE_PROFILES="$XPLANE_ROOT/Output/preferences/control profiles"

quarantine() {
	if [[ -d "$XPLANE_PLUGINS/$1" ]]; then
		mv -v "$XPLANE_PLUGINS/$1" -t "$XPLANE_PLUGINS_QUARANTINE"
	fi

	if ! [[ -d "$XPLANE_PLUGINS_QUARANTINE/$1" ]]; then
		die "Could not locate plugin '$1' in quarantine or otherwise"
	fi
}

unquarantine() {
	if [[ -d "$XPLANE_PLUGINS_QUARANTINE/$1" ]]; then
		mv -v "$XPLANE_PLUGINS_QUARANTINE/$1" -t "$XPLANE_PLUGINS"
	fi

	if ! [[ -d "$XPLANE_PLUGINS/$1" ]]; then
		die "Could not locate plugin '$1' in main plugins or otherwise"
	fi
}

keybind() {
	local key="$1" old="$2" new="$3"
	sed -r "s|^($key) $old|\1 $new|" -i "$XPLANE_PROFILES"/*.prf || true
	grep -E -H "^$key "                 "$XPLANE_PROFILES"/*.prf || true
}

usage() {
	err "$@"
	cat >&2 <<EOF

Usage: $0 PE|VATSIM
EOF
	exit 1
}

if ! (( $# == 1 )); then
	usage "Bad usage: got $# arguments, expected 1"
fi

case "$1" in
PE)
	log "Switching to PilotEdge"
	unquarantine xPilot
	unquarantine PilotEdge
	keybind '_joy_BUTN_use1309' 'xpilot/ptt' 'sim/operation/contact_atc'
	keybind '_joy_BUTN_use_desc1309' 'xPilot: Radio Push-to-Talk \(PTT\)' '(contact ATC)'
	;;

VATSIM)
	log "Switching to VATSIM (xPilot)"
	unquarantine PilotEdge
	unquarantine xPilot
	keybind '_joy_BUTN_use1309' 'sim/operation/contact_atc' 'xpilot/ptt'
	keybind '_joy_BUTN_use_desc1309' '\(contact ATC\)' 'xPilot: Radio Push-to-Talk (PTT)'
	;;

*)
	usage "Bad usage: got $1, expected PE or VATSIM"
	;;
esac
