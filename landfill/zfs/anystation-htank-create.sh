#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfslib.sh


#
# definitions
#

ZPOOL_CREATE_OPTS=(
    -o cachefile=/etc/zfs/zpool.cache

    -o ashift=12
    # -o autotrim=on
    -o feature@fast_dedup=enabled
    -o feature@block_cloning=enabled
    -o feature@empty_bpobj=enabled
    -O dnodesize=auto -O xattr=sa -O acltype=posixacl
    -O compression=zstd-11  # 207 MiB/s (220 MiB/s)
    -O checksum=sha256
    # -O dedup=sha256

    -O recordsize=1M
    -O special_small_blocks=256K

    -O atime=off
    -O relatime=off
)


#
# main
#

set -x

zpool create \
    "${ZPOOL_CREATE_OPTS[@]}" \
    htank -m /mnt/htank \
    raidz /dev/mapper/htank-{1,2,3,4} \
    log /dev/mapper/htank-log-1 \
    cache /dev/mapper/htank-cache-1 \
    special mirror /dev/mapper/htank-special-{1,2} \

zfs_allow_create htank operator

par1 \
    zfs create -p ::: \
    htank/DATA/{Archive,Backups,Files,Internal{,/{Bitcoin,Nextcloud}},Media,Public,Scratch,Torrents}
