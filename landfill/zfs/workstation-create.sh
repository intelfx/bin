#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfslib.sh


#
# args
#

declare -A _ARGS=(
    [-n|--name:]="ARG_NAME"
    [-o|--option:]="ARG_OPTIONS append"
    [--pool:]="ARG_POOL"
    [-P|--prefix:]="ARG_PREFIX"
    [-M|--mountpoint:]="ARG_MOUNTPOINT"
    [-u|--users:]="ARG_USERS split=, append"
)
parse_args _ARGS "$@"

NAME="${ARG_NAME-"test"}"
PREFIX="${ARG_PREFIX-"/target"}"
MOUNTPOINT="${ARG_MOUNTPOINT-"$PREFIX/$NAME"}"
POOL="${ARG_POOL-"rpool"}"
USERS=( "${ARG_USERS[@]}" )
OPTIONS=( "${ARG_OPTIONS[@]}" )

ZFS_OPTIONS=()
for o in "${OPTIONS[@]}"; do ZFS_OPTIONS+=( -o "$o" ); done

DATASET_ROOT="$POOL/ROOT/$NAME"
DATASET_DATA="$POOL/DATA/$NAME"
DATASET_SCRATCH="$POOL/SCRATCH/$NAME"

print_or() {
    local text
    text="$(cat)" && [[ "$text" ]] && printf "%s" "$text" || echo "$*"
}

log "Target name:                     ${NAME@Q}"
log "Target mountpoint:               ${MOUNTPOINT@Q}"
log "Target pool:                     ${POOL@Q}"
log "Target users to create:          $(join ', ' "${USERS[@]@Q}" | print_or "(none)")"
log "Target dataset options:          $(join ', ' "${OPTIONS[@]@Q}" | print_or "(none)")"
log "Target dataset for OS:           ${DATASET_ROOT@Q}"
log "Target dataset for user data:    ${DATASET_DATA@Q}"
log "Target dataset for scratch data: ${DATASET_SCRATCH@Q}"
read -r -s -n1 _


#
# main
#

set -x

! mountpoint -q "$MOUNTPOINT" || umount -R "$MOUNTPOINT"
zfs destroy -R "$DATASET_SCRATCH" ||:
zfs destroy -R "$DATASET_DATA" ||:
zfs destroy -R "$DATASET_ROOT" ||:

### "ROOT" ###
zfs create -u \
    "${ZFS_OPTIONS[@]}" \
    -o mountpoint="$MOUNTPOINT" \
    "$DATASET_ROOT"
zfs create -u \
    -o recordsize=1M \
    -o compression=zstd-19 \
    -o mountpoint="$MOUNTPOINT/var/lib/flatpak" \
    "$DATASET_ROOT/flatpak"
zfs create -u \
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
    -o mountpoint="$MOUNTPOINT/etc" \
    "$DATASET_ROOT/var/etc"
zfs create -u \
    -o mountpoint="$MOUNTPOINT/var/log" \
    "$DATASET_ROOT/var/log"
zfs create -u \
    -o mountpoint="$MOUNTPOINT/var/tmp" \
    "$DATASET_ROOT/var/tmp"
zfs create -u \
    -o recordsize=1M \
    -o mountpoint="$MOUNTPOINT/var/lib/systemd/coredump" \
    "$DATASET_ROOT/var/coredump"

### "DATA" ###
zfs create -u \
    "${ZFS_OPTIONS[@]}" \
    -o canmount=off \
    "$DATASET_DATA"
zfs create -u \
    -o mountpoint="$MOUNTPOINT/home" \
    "$DATASET_DATA/home"
zfs create -u \
    -o mountpoint="$MOUNTPOINT/root" \
    "$DATASET_DATA/home/root"

### "SCRATCH" ###
zfs create -u \
    "${ZFS_OPTIONS[@]}" \
    -o canmount=off \
    "$DATASET_SCRATCH"
zfs create -pp -u \
    -o mountpoint="$MOUNTPOINT/var/lib/libvirt/images" \
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
    -o recordsize=1M \
    -o compression=zstd-19 \
    "$DATASET_SCRATCH/containers/root/images"
zfs create -pp -u \
    "$DATASET_SCRATCH/containers/root/volumes"
zfs create -pp -u \
    -o mountpoint="$MOUNTPOINT/var/lib/docker" \
    "$DATASET_SCRATCH/docker/root"
zfs create -pp -u \
    -o recordsize=1M \
    -o compression=zstd-19 \
    "$DATASET_SCRATCH/docker/root/overlay2"
zfs create -pp -u \
    "$DATASET_SCRATCH/docker/root/volumes"
zfs create -pp -u \
    -o recordsize=1M \
    -o compression=zstd-19 \
    -o mountpoint="$MOUNTPOINT/var/lib/waydroid" \
    "$DATASET_SCRATCH/waydroid"
zfs create -u \
    -o mountpoint="$MOUNTPOINT/srv/build" \
    "$DATASET_SCRATCH/srv-build"
zfs create -u \
    -o mountpoint="$MOUNTPOINT/srv/repo" \
    "$DATASET_SCRATCH/srv-repo"
zfs create -u \
    -o mountpoint="$MOUNTPOINT/var/cache/pacman/pkg" \
    "$DATASET_SCRATCH/var-cache-pacman-pkg"

### USERS ###
for user in intelfx; do
    zfs create -pp -u \
        -o mountpoint="$MOUNTPOINT/home/$user/tmp/big" \
        "$DATASET_SCRATCH/user/$user"
    zfs create -pp -u \
        -o mountpoint="$MOUNTPOINT/home/$user/.cache" \
        "$DATASET_SCRATCH/cache/$user"
    zfs create -pp -u \
        -o recordsize=1M \
        -o compression=zstd-19 \
        -o mountpoint="$MOUNTPOINT/home/$user/.cache/Zeal/Zeal/docsets" \
        "$DATASET_SCRATCH/cache/$user/zeal-docsets"
    zfs create -pp -u \
        -o mountpoint="$MOUNTPOINT/home/$user/.local/share/containers" \
        "$DATASET_SCRATCH/containers/$user"
    zfs create -pp -u \
        -o recordsize=1M \
        -o compression=zstd-19 \
        "$DATASET_SCRATCH/containers/$user/images"
    zfs create -pp -u \
        "$DATASET_SCRATCH/containers/$user/volumes"
done

zfs mount -R "$DATASET_ROOT"
zfs mount -R "$DATASET_DATA"
zfs mount -R "$DATASET_SCRATCH"

{ set +x; } &>/dev/null
