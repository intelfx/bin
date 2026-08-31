#!/bin/bash

set -eo pipefail
shopt -s lastpipe
. lib.sh

_usage() {
	cat <<EOF
Usage: $0 LINUX-DIR
EOF
}


#
# args
#

declare -A _args=(
	[-h|--help]=ARG_USAGE
	[--enable-debug]=ARG_ZFS_DEBUG
	[--disable-debug]=ARG_ZFS_NODEBUG # no-op
	[--llvm]=ARG_LLVM
	[--host:]=ARG_HOST # autotools
	[--arch:]=ARG_ARCH # kernel
	[--]=ARGS
)
parse_args _args "$@" || usage
[[ ! $ARG_USAGE ]] || usage

case "${#ARGS[@]}" in
1) ARG_KERNEL_DIR="${ARGS[0]}" ;;
*) usage "expected 1 positional parameter" ;;
esac
ARG_ZFS_DIR="$PWD"
ARGS_ZFS_CONFIGURE=()
ARGS_KERNEL_CONFIGURE=()
ARGS_ENV=()

if [[ ${ARG_ZFS_DEBUG+set} ]]; then
	ARGS_ZFS_CONFIGURE+=(
		--enable-debug
	)
else
	ARGS_ZFS_CONFIGURE+=(
		--disable-debug
	)
fi

if [[ ${ARG_LLVM+set} ]]; then
	ARGS_KERNEL_CONFIGURE+=(
		LLVM=1
	)
	ARGS_ZFS_CONFIGURE+=(
		KERNEL_LLVM=1
	)
	ARGS_ENV+=(
		CC=clang
		CXX=clang++
	)
fi

if [[ ${ARG_ARCH+set} ]]; then
	ARGS_KERNEL_CONFIGURE+=(
		ARCH="$ARG_ARCH"
	)
	ARGS_ZFS_CONFIGURE+=(
		KERNEL_ARCH="$ARG_ARCH"
	)
fi

if [[ ${ARG_HOST+set} ]]; then
	if ! [[ ${ARG_LLVM+set} ]]; then
		ARGS_KERNEL_CONFIGURE+=(
			CROSS_COMPILE="$ARG_HOST-"
		)
		ARGS_ZFS_CONFIGURE+=(
			KERNEL_CROSS_COMPILE="$ARG_HOST-"
		)
	fi
	ARGS_ZFS_CONFIGURE+=(
		--host="$ARG_HOST"
	)
fi


#
# main
#

ARG_KERNEL_DIR="$(realpath -e "$ARG_KERNEL_DIR")"
ARG_ZFS_DIR="$(realpath -e "$ARG_ZFS_DIR")"

log "ZFS tree:             ${ARG_ZFS_DIR@Q}"
log "Kernel tree:          ${ARG_KERNEL_DIR@Q}"
log "Extra env vars:       ${ARGS_ENV[*]@Q}"
log "ZFS ./configure args: ${ARGS_ZFS_CONFIGURE[*]@Q}"
log "Kernel make args:     ${ARGS_KERNEL_CONFIGURE[*]@Q}"

setup_kernel() (
	local -; set -x
	cd "$1"
	env \
		"${ARGS_ENV[@]}" \
	kmake prepare \
		"${ARGS_KERNEL_CONFIGURE[@]}"
)

setup_zfs() (
	local -; set -x
	cd "$1"
	./autogen.sh
	env \
		"${ARGS_ENV[@]}" \
	./configure \
		--prefix=/usr \
		--with-config=kernel \
		--with-linux="$2" \
		--enable-linux-experimental \
		--enable-linux-builtin=yes \
		"${ARGS_ZFS_CONFIGURE[@]}"
	~/bin/devel/zfs-copy-builtin.sh \
		"$2"
)

setup_kernel "$ARG_KERNEL_DIR"
setup_zfs "$ARG_ZFS_DIR" "$ARG_KERNEL_DIR"
