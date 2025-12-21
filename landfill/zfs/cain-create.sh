#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfslib.sh

#
# definitions
#

BPOOL_DEVICES=(
    /dev/disk/by-partlabel/cain-XBOOTLDR
)
BPOOL_CREATE_OPTS=(
    -o compatibility=grub2
    -o cachefile=/etc/zfs/zpool.cache

    -o ashift=12
    -o autotrim=on
    -o cachefile=/etc/zfs/zpool.cache
    -O dnodesize=legacy -O xattr=sa -O acltype=posixacl
    -O compression=lz4
    -O checksum=sha256

    -O atime=off
    -O relatime=off
)

RPOOL_DEVICES=(
    /dev/disk/by-id/dm-name-cain-rpool-1
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

zpool destroy bpool ||:
blkdiscard -v -f "${BPOOL_DEVICES[@]}"
zpool create \
    "${BPOOL_CREATE_OPTS[@]}" \
    bpool -R /target -m /mnt/zfs/bpool -O canmount=off \
    "${BPOOL_DEVICES[@]}"

zfs_allow_to bpool operator

zpool destroy rpool ||:
blkdiscard -v -f "${RPOOL_DEVICES[@]}"
zpool create \
    "${RPOOL_CREATE_OPTS[@]}" \
    rpool -R /target -m /mnt/zfs/rpool -O canmount=off \
    "${RPOOL_DEVICES[@]}"

zfs_allow_to rpool operator

zfs create -u \
    -o canmount=off \
    bpool/BOOT
zfs create -u \
    -o mountpoint=/boot \
    bpool/BOOT/arch
