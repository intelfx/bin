#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfslib.sh

#
# definitions
#

BPOOL_DEVICES=(
    /dev/disk/by-partuuid/3140d069-9a4b-4002-9d4c-b0f887c5974e
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
    /dev/disk/by-id/dm-uuid-CRYPT-LUKS2-78c2172bac7a471594d396a3196ea068-*
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

zfs create -u \
    -o canmount=off \
    rpool/ROOT
zfs create -u \
    -o mountpoint=/nix \
    -o recordsize=1M \
    -o compression=zstd-19 \
    rpool/ROOT/nix
zfs create -u \
    -o mountpoint=/ \
    rpool/ROOT/arch
zfs create -u \
    -o recordsize=1M \
    -o compression=zstd-19 \
    rpool/ROOT/arch/usr
zfs create -u \
    -o recordsize=1M \
    -o compression=zstd-19 \
    rpool/ROOT/arch/opt
zfs create -u \
    rpool/ROOT/arch/var
zfs create -u \
    -o mountpoint=/etc \
    rpool/ROOT/arch/var/etc
zfs create -u \
    -o mountpoint=/log \
    rpool/ROOT/arch/var/log
zfs create -u \
    -o mountpoint=/tmp \
    rpool/ROOT/arch/var/tmp
zfs create -u \
    -o mountpoint=/var/lib/systemd/coredump \
    -o recordsize=1M \
    rpool/ROOT/arch/var/coredump

zfs create -u \
    -o canmount=off \
    rpool/DATA
zfs create -u \
    -o mountpoint=/mnt/data \
    -o compression=zstd-11 \
    rpool/DATA/data
# zfs create -u \
#     -o mountpoint=/var/lib/libvirt \
#     rpool/DATA/libvirt
zfs create -u \
    -o mountpoint=/home \
    rpool/DATA/home
zfs create -u \
    -o mountpoint=/root \
    rpool/DATA/home/root

zfs create -u \
    -o canmount=off \
    rpool/SCRATCH
zfs create -u \
    -o mountpoint=/mnt/scratch \
    rpool/SCRATCH/scratch
zfs create -u \
    -o mountpoint=/var/cache/pacman/pkg \
    rpool/SCRATCH/var-cache-pacman-pkg
zfs create -u \
    -o mountpoint=/srv/build \
    rpool/SCRATCH/srv-build

zfs create -pp -u \
    -o mountpoint=/home/intelfx/tmp/big \
    rpool/SCRATCH/user/intelfx
zfs create -pp -u \
    -o mountpoint=/home/intelfx/.cache \
    rpool/SCRATCH/cache/intelfx

zfs mount -R rpool/ROOT/arch
zfs mount -R rpool/DATA
zfs mount -R rpool/SCRATCH
zfs mount -R bpool/BOOT/arch
