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
