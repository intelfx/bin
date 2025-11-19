#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfslib.sh


#
# main
#

set -x

DATASET_ROOT="rpool/ROOT/able"
DATASET_DATA="rpool/DATA/able"
DATASET_SCRATCH="rpool/SCRATCH/able"
MOUNTPOINT="/target/able"

! mountpoint -q "$MOUNTPOINT" || umount -R "$MOUNTPOINT"
zfs destroy -R "$DATASET_SCRATCH" ||:
zfs destroy -R "$DATASET_DATA" ||:
zfs destroy -R "$DATASET_ROOT" ||:

zfs create -u \
    -o "mountpoint=$MOUNTPOINT" \
    "$DATASET_ROOT"
zfs create -u \
    -o "mountpoint=$MOUNTPOINT/var/lib/flatpak" \
    -o recordsize=1M \
    -o compression=zstd-19 \
    "$DATASET_ROOT/flatpak"
zfs create -u \
    -o "mountpoint=$MOUNTPOINT/nix" \
    -o recordsize=1M \
    -o compression=zstd-19 \
    "$DATASET_ROOT/nix"
zfs create -u \
    -o recordsize=1M \
    -o compression=zstd-19 \
    "$DATASET_ROOT/opt"
zfs create -u \
    -o recordsize=1M \
    -o compression=zstd-19 \
    "$DATASET_ROOT/usr"
zfs create -u \
    "$DATASET_ROOT/var"
zfs create -u \
    -o "mountpoint=$MOUNTPOINT/etc" \
    "$DATASET_ROOT/var/etc"
zfs create -u \
    -o "mountpoint=$MOUNTPOINT/var/log" \
    "$DATASET_ROOT/var/log"
zfs create -u \
    -o "mountpoint=$MOUNTPOINT/var/tmp" \
    "$DATASET_ROOT/var/tmp"
zfs create -u \
    -o "mountpoint=$MOUNTPOINT/var/lib/systemd/coredump" \
    -o recordsize=1M \
    "$DATASET_ROOT/var/coredump"

zfs create -u \
    -o canmount=off \
    "$DATASET_DATA"
zfs create -u \
    -o "mountpoint=$MOUNTPOINT/home" \
    "$DATASET_DATA/home"
zfs create -u \
    -o "mountpoint=$MOUNTPOINT/root" \
    "$DATASET_DATA/home/root"

zfs create -u \
    -o canmount=off \
    "$DATASET_SCRATCH"
zfs create -pp -u \
    -o mountpoint="$MOUNTPOINT/var/lib/libvirt" \
    -o recordsize=4k \
    "$DATASET_SCRATCH/libvirt"
zfs create -pp -u \
    -o mountpoint="$MOUNTPOINT/var/lib/machines" \
    "$DATASET_SCRATCH/machines"
zfs create -pp -u \
    "$DATASET_SCRATCH/machines/arch"
zfs create -pp -u \
    -o mountpoint="$MOUNTPOINT/var/lib/containers" \
    "$DATASET_SCRATCH/containers/root"
zfs create -pp -u \
    -o mountpoint="$MOUNTPOINT/var/lib/containers/storage/overlay" \
    -o recordsize=1M \
    -o compression=zstd-19 \
    "$DATASET_SCRATCH/containers/root/overlay"
zfs create -pp -u \
    -o mountpoint="$MOUNTPOINT/var/lib/waydroid" \
    -o recordsize=1M \
    -o compression=zstd-19 \
    "$DATASET_SCRATCH/waydroid"
zfs create -u \
    -o "mountpoint=$MOUNTPOINT/srv/build" \
    "$DATASET_SCRATCH/srv-build"
zfs create -u \
    -o "mountpoint=$MOUNTPOINT/srv/repo" \
    "$DATASET_SCRATCH/srv-repo"

for user in intelfx; do
    zfs create -pp -u \
        -o "mountpoint=$MOUNTPOINT/home/$user/tmp/big" \
        "$DATASET_SCRATCH/user/$user"
    zfs create -pp -u \
        -o "mountpoint=$MOUNTPOINT/home/$user/.cache" \
        "$DATASET_SCRATCH/cache/$user"
    zfs create -pp -u \
        -o mountpoint="$MOUNTPOINT/home/$user/.local/share/containers" \
        "$DATASET_SCRATCH/containers/$user"
    zfs create -pp -u \
        -o mountpoint="$MOUNTPOINT/home/$user/.local/share/containers/storage/overlay" \
        -o recordsize=1M \
        -o compression=zstd-19 \
        "$DATASET_SCRATCH/containers/$user/overlay"
    done

zfs mount -R "$DATASET_ROOT"
zfs mount -R "$DATASET_DATA"
zfs mount -R "$DATASET_SCRATCH"
