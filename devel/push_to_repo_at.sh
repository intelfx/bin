#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=../lib/lib.sh
. lib.sh

_usage() {
	cat <<-EOF
Usage: $0 (HOST:PATH | HOST:REPO-NAME) FILES...
EOF
}

declare -A _args=(
	['-h|--help']="ARG_USAGE"
	['--']="ARGS"
)

parse_args _args "$@" || usage

if (( ${#ARGS[@]} < 2 )); then
	usage "Expected at least 2 arguments, got ${#ARGS[@]}"
fi

ARG_TARGET="${ARGS[0]}"
ARG_FILES=("${ARGS[@]:1}")

if ! [[ $ARG_TARGET =~ ^([^:]+):(.+)$ ]]; then
	usage "Invalid target: ${ARG_TARGET@Q}"
fi

ARG_HOST="${BASH_REMATCH[1]}"
ARG_TARGET="${BASH_REMATCH[2]}"
if [[ $ARG_TARGET == /* ]]
then TARGET_MODE=path
else TARGET_MODE=name
fi


#
# main
#

remote_main() {
	# NB: this will be serialized via declare -f and executed remotely
	#     no usual environment is available, including lib.sh

	set -eo pipefail
	shopt -s lastpipe

	WORKDIR="$(realpath -qe "${BASH_SOURCE[0]%/*}")"
	rm -f "${BASH_SOURCE[0]}"

	# shellcheck disable=SC2329
	cleanup() {
		rm -rf "${WORKDIR:?}"
	}
	trap cleanup EXIT

	exec 9>&2
	log() {
		echo >&9 "remote: $*"
	}
	err() {
		echo >&9 "remote: error: $*"
	}
	die() {
		err "$*"
		exit 1
	}
	exec &> >(
		# can't meaningfully pass the very outermost $TERM here, so no point in doing things right -- hardcode ANSI sequences
		_prefix=$'\e[92m'
		_suffix=$'\e[0m'
		while IFS= read -r line; do
			echo >&9 "${_prefix}remote: log: $line${_suffix}"
		done
	)

	if ! command -v repoctl &>/dev/null; then
		die "repoctl is not installed"
	fi
	if ! command -v tomlq &>/dev/null; then
		die "tomlq is not installed"
	fi

	local ARG_TARGET="$1"
	local TARGET_MODE="$2"
	local ARG_FILES=( "${@:3}" )
	# input arguments are file names, convert to absolute paths
	ARG_FILES=( "${ARG_FILES[@]/#/$WORKDIR/}" )

	log "adding ${#ARG_FILES[@]} files to repo ${ARG_TARGET@Q}"

	local repoctl_conf_toml
	repoctl_conf_toml="$(repoctl conf show --template)"
	tomlq_conf() {
		tomlq "$@" <<<"$repoctl_conf_toml"
	}

	if [[ $TARGET_MODE == path ]]; then
		# shellcheck disable=SC2016
		local tomlq_prog='.
		| .profiles
		| to_entries
		| map(select(
			.value.repo | test("^" + $path + "/[^/]+$")
		))
		| map(.key)
		'
		tomlq_conf --arg path "$ARG_TARGET" "$tomlq_prog" | readarray -t PROFILES
		if (( ${#PROFILES[@]} < 1 )); then
			die "path ${ARG_TARGET@Q} is not configured in repoctl"
		fi
		if (( ${#PROFILES[@]} != 1 )); then
			die "path ${ARG_TARGET@Q} matches multiple repoctl profiles: $(join ", " "${PROFILES[@]}")"
		fi
	elif [[ $TARGET_MODE == name ]]; then
		# validate that the profile exists
		if ! repoctl -P "$ARG_TARGET" list >/dev/null; then
			die "repoctl profile ${ARG_TARGET@Q} does not exist"
		fi
		PROFILES=("$ARG_TARGET")
	fi

	repoctl -P "${PROFILES[@]}" add --move "${ARG_FILES[@]}"
	# die "kaboom"
}


WORKDIR="$(mktemp -d --tmpdir "repotransfer.XXXXXX")"
cleanup() {
	rm -rf "${WORKDIR:?}"
}
trap cleanup EXIT

cp -a "${ARG_FILES[@]}" -t "$WORKDIR"
# compute basenames of the files being transferred
_arg_files=("${ARG_FILES[@]##*/}")
{
	declare -f remote_main
	echo "remote_main ${ARG_TARGET@Q} ${TARGET_MODE@Q} ${_arg_files[*]@Q}"
} | install -m755 /dev/stdin "$WORKDIR/script.sh"

log "transferring ${#ARG_FILES[@]} files to remote host ${ARG_HOST@Q}"

ssh_quoted() {
	local opts=()
	while [[ $1 == -* ]]; do
		opts+=("$1")
		shift
	done
	local host="$1"
	shift
	local args="${*@Q}"

	ssh "${opts[@]}" -- "$host" "$args"
}

# shellcheck disable=SC2016
tar -c --remove-files -C "$WORKDIR" . | ssh_quoted "$ARG_HOST" bash -c '
{ . /etc/profile; . ~/.profile; } </dev/null
set -eo pipefail
WORKDIR="$(mktemp -d --tmpdir "repotransfer.XXXXXX")"
tar -x -C "$WORKDIR"
exec "$WORKDIR/script.sh"
' || {
	die "failed to transfer files, exiting"
}

log "done, removing ${#ARG_FILES[@]} source files"
rm -f "${ARG_FILES[@]}"
