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
    mmc-8GTF4R_0xc79b5216-part2
)
RPOOL_CREATE_OPTS=(
    "${ZPOOL_CREATE_OPTS[@]}"
    -O compression=zstd-1
)

TANK_NAME=tank
TANK_DEVICES=(
    dm-uuid-CRYPT-LUKS2-e79b0ffe65e145f2a371196ac4d2d0e8-tank-1
)
TANK_CREATE_OPTS=(
    "${ZPOOL_CREATE_OPTS[@]}"
    -O compression=zstd-1
)


#
# main
#

set -x

zpool destroy "$TANK_NAME" ||:
blkdiscard -v -f "/dev/disk/by-id/${TANK_DEVICES[@]}"
zpool create \
    "${TANK_CREATE_OPTS[@]}" \
    "$TANK_NAME" -m "/mnt/zfs/$TANK_NAME" -O canmount=off \
    "${TANK_DEVICES[@]}"

zfs_allow_to "$TANK_NAME" operator
