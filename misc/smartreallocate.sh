#!/bin/bash

. lib.sh

SECTOR_LOG_PER_PHYS=4
POLL_TIMEOUT=15

function hd_rewrite() {
	local dev="$1"
	local sector="$2"
	sector="$(( sector - sector%SECTOR_LOG_PER_PHYS ))"

	local i
	for (( i=sector; i < sector+SECTOR_LOG_PER_PHYS; ++i )); do
		sudo hdparm --yes-i-know-what-i-am-doing --write-sector "$i" "$dev"
	done
}

function hd_test_status() {
	local dev="$1"
	sudo smartctl -c "$dev" | grep -Po 'Self-test execution status: *\( *\K[0-9]+'
}

function hd_test_first_error() {
	dev="$1"
	sudo smartctl -l selftest "$dev" | grep -Po '# 1 *Selective offline *Completed: read failure *[0-9]+% *[0-9]+ *\K[0-9]+'
}

function hd_test_launch() {
	dev="$1"
	region="$2"
	timeout="$POLL_TIMEOUT"
	sudo smartctl -t select,$region "$dev"
}

dev_arg="$1"
dev="$1"
if ! [[ -b $dev ]]; then
	die "Invalid block device: $dev"
fi

region_arg="$2"
region="$2"

# parse partition region specification
if [[ -b $region ]]; then
	region="$(realpath -qe "$region")"
	if ! [[ $region == $dev* ]]; then
		die "Invalid region partition: $region_arg does not seem to relate to $dev_arg"
	fi
	region="$(basename "$region")"
	if ! [[ -e "/sys/class/block/$region" ]]; then
		die "Invalid region specification: /sys/class/block/$region does not exist"
	fi
	region="$(< /sys/class/block/$region/start)+$(< /sys/class/block/$region/size)"
fi

# parse start+size region specification
if [[ $region =~ ([0-9]+)\+([0-9]+) ]]; then
	region=${BASH_REMATCH[1]}-$(( ${BASH_REMATCH[1]} + ${BASH_REMATCH[2]} ))
fi

# parse start-end region specification
if [[ $region =~ ([0-9]+)\-([0-9]+|max) ]]; then
	region_start=${BASH_REMATCH[1]}
	region_end=${BASH_REMATCH[2]}
else
	die "Invalid region specification: failed to normalize, got $region"
fi

timeout="$POLL_TIMEOUT"
while :; do
	code="$(hd_test_status "$dev")"
	case "$code" in
		24[0-9])
			log "[$dev]: $code: test in progress -- waiting for $timeout seconds"
			sleep "$timeout"
			if (( timeout < 60 )); then
				: $(( timeout *= 2 ))
			fi
			test_was_running=1
			;;
		12[0-1])
			log "[$dev]: $code: test read failure"
			if ! sector="$(hd_test_first_error "$dev")"; then
				die "[$dev]: $code: could not parse selftest log"
			fi
			log "[$dev]: $code: test read failure @ $sector -- rewriting"
			hd_rewrite "$dev" "$sector"
			log "[$dev]: $code: re-starting test"
			hd_test_launch "$dev" "$sector-$region_end"
			;;
		*)
			if (( test_was_running )); then
				log "[$dev]: $code: test completed -- exiting"
				break
			else
				log "[$dev]: $code: no test in progress -- starting"
				hd_test_launch "$dev" "$region"
			fi
			;;
	esac
done
