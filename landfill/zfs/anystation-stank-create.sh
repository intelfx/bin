#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfslib.sh


#
# definitions
#

ZPOOL_CREATE_OPTS=(
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

zpool create \
    "${ZPOOL_CREATE_OPTS[@]}" \
    stank -m /mnt/stank \
    /dev/mapper/stank-1 \
    log /dev/mapper/stank-log-1 \

zfs_allow_create stank operator
