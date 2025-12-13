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

zpool get -H altroot "$POOL" \
    | IFS=$'\t' read _ _ value _

POOL_ALTROOT=""
if [[ $value == /?* ]]; then
    POOL_ALTROOT="$value"
elif [[ $value == - ]]; then
    :
else
    err "Unexpected altroot: ${value@Q}"
fi


print_or() {
    local text
    text="$(cat)" && [[ "$text" ]] && printf "%s" "$text" || echo "$*"
}

log "Target name:                     ${NAME@Q}"
log "Target mountpoint:               ${MOUNTPOINT@Q}"
log "Target pool:                     ${POOL@Q}"
log "Target pool altroot:             $(<<<"${POOL_ALTROOT:+"${POOL_ALTROOT@Q}"}" print_or "(none)")"
log "Target users to create:          $(join ', ' "${USERS[@]@Q}" | print_or "(none)")"
log "Target dataset options:          $(join ', ' "${OPTIONS[@]@Q}" | print_or "(none)")"
log "Target dataset for OS:           ${DATASET_ROOT@Q}"
log "Target dataset for user data:    ${DATASET_DATA@Q}"
log "Target dataset for scratch data: ${DATASET_SCRATCH@Q}"
read -r -s -n1 _


#
# functions
#

_zfs_create_one() {
    local dataset="$1" mountpoint="$2"
    local -a options=("${@:3}")

    if ! [[ $is_global ]]; then
        case "$dataset" in
        ROOT?(/*))    dataset="$DATASET_ROOT${dataset#ROOT}" ;;
        DATA?(/*))    dataset="$DATASET_DATA${dataset#DATA}" ;;
        SCRATCH?(/*)) dataset="$DATASET_SCRATCH${dataset#SCRATCH}" ;;
        *)            die "zfs_create: invalid dataset: ${dataset@Q}" ;;
        esac

        case "$mountpoint" in
        "") ;;
        /)   options+=( -o mountpoint="$MOUNTPOINT" ) ;;
        /?*) options+=( -o mountpoint="$MOUNTPOINT$mountpoint" ) ;;
        *)   die "zfs_create: invalid mountpoint: ${mountpoint@Q}" ;;
        esac
    else
        dataset="$POOL/$dataset"

        case "$mountpoint" in
        "") ;;
        /*) options+=( -o mountpoint="$mountpoint" ) ;;
        *)  die "zfs_create: invalid mountpoint: ${mountpoint@Q}" ;;
        esac
    fi

    local -
    set -x
    zfs create -u -pp "${options[@]}" "$dataset"
}

zfs_create() {
    local is_global
    local options=()
    local args=()
    while (( $# )); do
        case "$1" in
        --global)  is_global=1 ;;
        --root)    options+=( "${ZFS_OPTIONS[@]}" ) ;;
        --os)      options+=( -o recordsize=1M -o compression=zstd-19 -o dedup=sha256 ) ;;
        --big)     options+=( -o recordsize=1M ) ;;
        -o)        options+=( "$1" "$2" ); shift ;;
        -o?*)      options+=( "$1" ) ;;
        -p|-pp)    options+=( "$1" ) ;;
        --nomount) options+=( -o canmount=off ) ;;
        -*)        die "zfs_create: invalid flag: ${1@Q}" ;;
        *)         args+=("$1") ;;
        esac
        shift
    done

    local dataset mountpoint
    case "${#args[@]}" in
    2) mountpoint="${args[1]}" ;&
    1) dataset="${args[0]}" ;;
    *) die "zfs_create: invalid args, expected 1 or 2: ${args[@]@Q}" ;;
    esac

    _zfs_create_one "$dataset" "$mountpoint" "${options[@]}"
}

zfs_create_podman() {
    local options=()
    local args=()
    while (( $# )); do
        case "$1" in
        -*) options+=("$1") ;;
        *)  args+=("$1") ;;
        esac
        shift
    done

    local dataset mountpoint
    case "${#args[@]}" in
    2) dataset="${args[0]}"; mountpoint="${args[1]}" ;;
    *) die "zfs_create_podman: invalid args, expected 2: ${args[@]@Q}" ;;
    esac

    zfs_create      "${options[@]}" "$dataset" "$mountpoint"
    zfs_create --os "${options[@]}" "$dataset/images"
    zfs_create      "${options[@]}" "$dataset/volumes"
}

zfs_create_docker() {
    local options=()
    local args=()
    while (( $# )); do
        case "$1" in
        -*) options+=("$1") ;;
        *)  args+=("$1") ;;
        esac
        shift
    done

    local dataset mountpoint
    case "${#args[@]}" in
    2) dataset="${args[0]}"; mountpoint="${args[1]}" ;;
    *) die "zfs_create_docker: invalid args, expected 2: ${args[@]@Q}" ;;
    esac

    zfs_create      "${options[@]}" "$dataset" "$mountpoint"
    zfs_create --os "${options[@]}" "$dataset/overlay2"
    zfs_create      "${options[@]}" "$dataset/volumes"
}


#
# main
#

set -x

! mountpoint -q "$POOL_ALTROOT$MOUNTPOINT" || umount -R "$POOL_ALTROOT$MOUNTPOINT"
zfs destroy -R "$DATASET_SCRATCH" ||:
zfs destroy -R "$DATASET_DATA" ||:
zfs destroy -R "$DATASET_ROOT" ||:

{ set +x; } &>/dev/null

### "ROOT" ###
zfs_create --root   "ROOT"                                  "/"
zfs_create --os     "ROOT/flatpak"                          "/var/lib/flatpak"
zfs_create --os     "ROOT/nix"
zfs_create --os     "ROOT/opt"
zfs_create --os     "ROOT/usr"
zfs_create --os     "ROOT/usr/debug"                        "/usr/lib/debug"
zfs_create --os     "ROOT/usr/images"                       "/var/lib/libvirt/images"
zfs_create          "ROOT/var"
zfs_create          "ROOT/var/etc"                          "/etc"
zfs_create          "ROOT/var/log"
zfs_create          "ROOT/var/tmp"
zfs_create --big    "ROOT/var/coredump"                     "/var/lib/systemd/coredump"

### "DATA" ###
zfs_create --root   "DATA"                                  --nomount
zfs_create          "DATA/data"                             "/mnt/rpool"                           --global
zfs_create          "DATA/home"                             "/home"
zfs_create          "DATA/home/root"                        "/root"

### "SCRATCH" ###
zfs_create --root   "SCRATCH"                               --nomount
zfs_create          "SCRATCH/netdata"                       "/var/lib/netdata"
zfs_create          "SCRATCH/netdata/db"                    "/var/cache/netdata"
zfs_create_podman   "SCRATCH/containers/root"               "/var/lib/containers"
zfs_create_docker   "SCRATCH/docker/root"                   "/var/lib/docker"

if [[ $NAME == anystation ]]; then
zfs_create          "SCRATCH/scratch"                       "/mnt/scratch"                         --global
zfs_create          "SCRATCH/scratch/big"                                                          --global
zfs_create          "SCRATCH/scratch/borg"                                                         --global
zfs_create          "SCRATCH/scratch/cache"                                                        --global
zfs_create --big    "SCRATCH/var-cache-pacman-pkg"          --nomount                              --global
zfs_create          "SCRATCH/var-cache-pacman-pkg/arch"     "/var/cache/pacman/pkg"                --global
zfs_create          "SCRATCH/var-cache-pacman-pkg/steamos"  "/var/cache/pacman/pkg-steamos"        --global
# zfs_create          "SCRATCH/machines"                      "/var/lib/machines"
# zfs_create          "SCRATCH/machines/arch"
zfs_create          "SCRATCH/libvirt"                       "/var/lib/libvirt"
zfs_create          "SCRATCH/incus"                         "/var/lib/incus"
zfs_create          "SCRATCH/k3s"                           "/var/lib/rancher/k3s"
zfs_create          "SCRATCH/kubelet"                       "/var/lib/kubelet"
fi

if [[ $NAME == stratofortress ]]; then
#zfs_create --os     "SCRATCH/waydroid"                      "/var/lib/waydroid"
zfs_create          "SCRATCH/srv-build"                     "/srv/build"
zfs_create          "SCRATCH/srv-build/cache"
zfs_create --os     "SCRATCH/srv-build/chroot"
zfs_create --big    "SCRATCH/srv-build/src"
zfs_create          "SCRATCH/srv-build/work"
zfs_create --big    "SCRATCH/srv-repo"                      "/srv/repo"
zfs_create --big    "SCRATCH/srv-flatpak"                   "/srv/flatpak"
fi

### USERS ###
for user in "${USERS[@]}"; do
zfs_create          "SCRATCH/user/$user"                    "/home/$user/tmp/big"
zfs_create          "SCRATCH/cache/$user"                   "/home/$user/.cache"
# zfs_create --os     "SCRATCH/cache/$user/zeal-docsets"      "/home/$user/.cache/Zeal/Zeal/docsets"
zfs_create_podman   "SCRATCH/containers/$user"              "/home/$user/.local/share/containers"
done

### HACKS ###
if [[ $NAME == able ]]; then
user=intelfx
zfs_create          "SCRATCH/borg"                          "/home/$user/.cache/borg"
fi

set -x

# zfs mount -R "$DATASET_ROOT"
# zfs mount -R "$DATASET_DATA"
# zfs mount -R "$DATASET_SCRATCH"

{ set +x; } &>/dev/null
