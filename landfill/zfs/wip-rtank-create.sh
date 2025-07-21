#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfslib.sh


#
# definitions
#

ZPOOL_CREATE_OPTS=(
    -o cachefile=/etc/zfs/zpool.cache

    # -o ashift=12
    -o autotrim=on
    -o feature@fast_dedup=enabled
    -o feature@block_cloning=enabled
    -o feature@empty_bpobj=enabled
    -O dnodesize=auto -O xattr=sa -O acltype=posixacl
    -O compression=lz4
    # -O checksum=sha256

    -O atime=off
    -O relatime=off

    -O redundant_metadata=none
    -O sync=disabled
)


#
# main
#

set -x

zpool create \
    "${ZPOOL_CREATE_OPTS[@]}" \
    rtank -m /mnt/rtank -R /mnt \
    /dev/vda

zfs_allow_create rtank operator
