#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfslib.sh

#
# definitions
#

RPOOL_DEVICES=(
    /dev/disk/by-id/dm-name-anystation-rpool-1
)
RPOOL_CREATE_OPTS=(
    -o cachefile=/etc/zfs/zpool.cache

    -o ashift=12
    -o autotrim=on
    -o feature@fast_dedup=enabled
    -o feature@block_cloning=enabled
    -o feature@empty_bpobj=enabled
    -O dnodesize=auto -O xattr=sa -O acltype=posixacl
    -O compression=zstd-1  # 5231 MiB/s (5143 MiB/s)
    -O checksum=sha256

    -O atime=off
    -O relatime=off
)


#
# main
#

set -x

zpool destroy rpool ||:
blkdiscard -v -f "${RPOOL_DEVICES[@]}"
zpool create \
    "${RPOOL_CREATE_OPTS[@]}" \
    rpool -R /target -m /mnt/zfs/rpool -O canmount=off \
    "${RPOOL_DEVICES[@]}" \

zfs_allow_create rpool operator
