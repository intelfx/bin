#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfslib.sh


#
# definitions
#

ZPOOL_CREATE_OPTS=(
    -o ashift=12
    -o autotrim=on
    -o cachefile=none
    -o feature@fast_dedup=enabled
    -o feature@block_cloning=enabled
    -o feature@empty_bpobj=enabled
    -O acltype=posixacl -O xattr=sa -O dnodesize=auto
    -O compression=lz4
)


#
# main
#

set -x

zpool create \
    "${ZPOOL_CREATE_OPTS[@]}" \
    test -m /test \
    /dev/ram0

zfs_allow_create test operator


par1 \
    zfs create -p \
    ::: test/ROOT/sub{1,2,3,4}
