#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=./zfslib.sh
. "${BASH_SOURCE%/*}/zfslib.sh"

#
# definitions
#

# TODO bpool
# XBOOTLDR is broken on anystation for some reason

RPOOL_NAME=rpool
RPOOL_DEVICES=(
	/dev/disk/by-id/dm-name-anystation-rpool-1
)
RPOOL_CREATE_OPTS=(
	"${ZPOOL_CREATE_OPTS[@]}"
	-O compression=zstd-1  # 5231 MiB/s (5143 MiB/s)
	-O checksum=sha256
)


#
# main
#

set -x

zpool destroy "${RPOOL_NAME}" ||:
blkdiscard -v -f "${RPOOL_DEVICES[@]}"
zpool create \
	"${RPOOL_CREATE_OPTS[@]}" \
	"${RPOOL_NAME}" -R /target -m "/mnt/zfs/${RPOOL_NAME}" -O canmount=off \
	"${RPOOL_DEVICES[@]}" \
	# EOL

zfs_allow_create "${RPOOL_NAME}" operator
