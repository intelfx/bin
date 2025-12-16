#!/bin/bash

. lib.sh || exit

_usage() {
	cat <<EOF
Usage: $0 [ARGS...]
EOF
}


#
# args
#

declare -A _args=(
	[-h|--help]=ARG_USAGE
	#[--]=ARGS
)
parse_args _args "$@" || usage
[[ ! $ARG_USAGE ]] || usage

#
# main
#

function test_one() {
	local -a args=( "$@" )
	local workdir

	eval "$(ltraps)"

	loud "BENCHMARKING ${args[*]}"

	workdir="$(mktemp --tmpdir -d -- borgtest.XXXXXXXXXX)"
	ltrap "rm -rf ${workdir@Q}"

	mkdir -p "$workdir"/{repo,files}
	borg init "${args[@]}" "$workdir/repo" &>/dev/null
	borg benchmark crud "$workdir/repo" "$workdir/files"
}

ENCRYPTION=(
	# none
	# authenticated{,-blake2}
	repokey{,-blake2}
)

eval "$(globaltraps)"

export BORG_PASSPHRASE="$(pwgen -s 32 1)"

for e in "${ENCRYPTION[@]}"; do
	test_one -e "$e"
	sync
	sleep 10
done
