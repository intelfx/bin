#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=./zfslib.sh
. "${BASH_SOURCE%/*}/zfslib.sh"

#
# definitions
#

RPOOL_NAME=rpool
RPOOL_DEVICES=(
	/dev/disk/by-partlabel/drone-rpool-1
)
RPOOL_CREATE_OPTS=(
	"${ZPOOL_CREATE_OPTS[@]}"
	-O compression=zstd-1
	-O checksum=fletcher4
)

TANK_NAME=tank
TANK_DEVICES=(
	/dev/disk/by-id/nvme-Samsung_SSD_980_250GB_S64BNU0X503362M_1
)
TANK_CREATE_OPTS=(
	"${ZTANK_CREATE_OPTS[@]}"
	-O compression=zstd-1
	-O checksum=fletcher4
)


#
# main
#

set -x

zpool destroy "$RPOOL_NAME" ||:
blkdiscard -v -f "${RPOOL_DEVICES[@]}"
zpool create \
	"${RPOOL_CREATE_OPTS[@]}" \
	"$RPOOL_NAME" -R /target -m "/mnt/zfs/$RPOOL_NAME" \
	"${RPOOL_DEVICES[@]}" \

zfs_allow_create "$RPOOL_NAME" operator

zpool destroy "$TANK_NAME" ||:
blkdiscard -v -f "${TANK_DEVICES[@]}"
zpool create \
	"${TANK_CREATE_OPTS[@]}" \
	"$TANK_NAME" -m "/mnt/zfs/$TANK_NAME" \
	"${TANK_DEVICES[@]}" \

zfs_allow_create "$TANK_NAME" operator
