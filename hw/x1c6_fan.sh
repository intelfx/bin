#!/bin/bash

. lib.sh || exit 1

usage() {
	cat >&2 <<EOF
$0 -- control x1c6 fan

Usage: $0 <off|on|auto|N> ...

off, on, auto	configure fan
N		sleep N seconds
EOF

	exit 1
}

if ! (( $# )); then
	usage
fi

SYSFS_NODE="$(realpath -qe /sys/devices/platform/thinkpad_hwmon/hwmon/hwmon*)"
if ! [[ -d "$SYSFS_NODE" ]]; then
	die "Could not find thinkpad_hwmon sysfs node (tried: $SYSFS_NODE)"
fi

if ! [[ -w "$SYSFS_NODE/pwm1" && -w "$SYSFS_NODE/pwm1_enable" ]]; then
	die "Could not find or write to thinkpad_hwmon fan controls (tried: $SYSFS_NODE)"
fi

try_write() {
	local name="$1" node="$2" key="$3" value="$4"
	local output
	if output="$( (echo "$value" > "$node/$key") 2>&1 )"; then
		echo "  ${0##*/} $name: [$key <- $value]" >&2
	else
		echo "  ${0##*/} $name: [$key <- $value]: $output" >&2
		return 1
	fi
}

try_read() {
	local name="$1" node="$2" key="$3"
	local output
	if output="$( (cat "$node/$key") 2>&1 )"; then
		echo "  ${0##*/} $name: [$key == $output]" >&2
		echo "$output"
	else
		echo "  ${0##*/} $name: [$key]: $output" >&2
		return 1
	fi
}

for arg; do
	case "$arg" in
	max)
		try_write "$arg" "$SYSFS_NODE" "pwm1_enable" "0"

		while :; do
			rpm="$(try_read "$arg" "$SYSFS_NODE" "fan1_input")"
			if (( rpm == 65535 )); then
				die "bad rpm"
			fi
			if (( rpm > 5500 )); then
				break
			fi
			sleep 1
		done
		;;
	on)
		try_write "$arg" "$SYSFS_NODE" "pwm1_enable" "1"
		try_write "$arg" "$SYSFS_NODE" "pwm1" "255"

		while :; do
			rpm="$(try_read "$arg" "$SYSFS_NODE" "fan1_input")"
			if (( rpm == 65535 )); then
				die "bad rpm"
			fi
			if (( rpm > 5000 )); then
				break
			fi
			sleep 1
		done
		;;
	on=[0-9]*)
		value="${arg#*=}"
		try_write "$arg" "$SYSFS_NODE" "pwm1_enable" "1"
		try_write "$arg" "$SYSFS_NODE" "pwm1" "$value"
		try_write "$arg" "$SYSFS_NODE" "pwm1_enable" "1"
		;;

	off)
		try_write "$arg" "$SYSFS_NODE" "pwm1_enable" "1"
		try_write "$arg" "$SYSFS_NODE" "pwm1" "0"
		try_write "$arg" "$SYSFS_NODE" "pwm1_enable" "1"

		while :; do
			rpm="$(try_read "$arg" "$SYSFS_NODE" "fan1_input")"
			if (( rpm == 0 )); then
				break
			fi
			sleep 1
		done
		;;

	auto)
		try_write "$arg" "$SYSFS_NODE" "pwm1_enable" "2"
		;;

	sleep=[0-9]*)
		value="${arg#*=}"
		sleep "$value"
		;;

	[0-9]*)
		sleep "$arg"
		;;

	*)
		usage
		;;
	esac
done
