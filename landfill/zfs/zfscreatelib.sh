#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfslib.sh


#
# args
#

_usage() {
    cat <<EOF
Usage: $LIB_ARGV0 -n|--name MACHINE-NAME --pool POOL-NAME -P|--prefix /path/to/prefix [-M MOUNTPOINT] [-u|--users LIST,OF,USERS] [--dedup]

Options:
    -n, --name MACHINE-NAME     Inserted into dataset names (pool/ROOT/machine/var/log)
    --pool POOL-NAME            Pool name to create datasets on (default: rpool)
    --prefix /path/to/prefix    Pool mountpoint prefix (default: /target)
    -M, --mountpoint MOUNTPOINT Pool mountpoint (default: \$prefix/\$poolname)
    -u, --users USER-LIST       Which users to create datasets for (comma-separated)
    --dedup                     Enable deduplication on OS datasets
EOF
}

declare -A _ARGS=(
    [--help]="ARG_USAGE"
    [-n|--name:]="ARG_NAME"
    [-o|--option:]="ARG_OPTIONS append"
    [--pool:]="ARG_POOL"
    [-P|--prefix:]="ARG_PREFIX"
    [-M|--mountpoint:]="ARG_MOUNTPOINT"
    [-u|--users:]="ARG_USERS split=, append"
    [--dedup::]="ARG_DEDUP default=on"
)
parse_args _ARGS "$@"

if [[ ${ARG_USAGE+set} ]]; then
    usage
fi

NAME="${ARG_NAME-"test"}"
PREFIX="${ARG_PREFIX-"/target"}"
MOUNTPOINT="${ARG_MOUNTPOINT-"$PREFIX/$NAME"}"
POOL="${ARG_POOL-"rpool"}"
USERS=( "${ARG_USERS[@]}" )
OPTIONS=( "${ARG_OPTIONS[@]}" )

ZFS_OPTIONS=()
ZFS_BIG_OPTIONS=( -o recordsize=1M )
ZFS_OS_OPTIONS=( -o recordsize=1M -o compression=zstd-19 )

for o in "${OPTIONS[@]}"; do ZFS_OPTIONS+=( -o "$o" ); done

if [[ ${ARG_DEDUP+set} ]]; then
    ZFS_OS_OPTIONS+=( -o "dedup=${ARG_DEDUP:-on}" )
fi

zpool get -H altroot "$POOL" \
    | IFS=$'\t' read _ _ value _

POOL_ALTROOT=""
if [[ $value == /?* ]]; then
    POOL_ALTROOT="$value"
elif [[ $value == - ]]; then
    :
else
    err "Unexpected pool altroot: ${value@Q}"
fi

zfs get -H mountpoint "$POOL" \
    | IFS=$'\t' read _ _ value _
POOL_MOUNTPOINT=""
if [[ $value == /* ]]; then
    POOL_MOUNTPOINT="${value#"$POOL_ALTROOT"}"
elif [[ $value == none ]]; then
    :
else
    err "Unexpected pool own mountpoint: ${value@Q} (altroot=${POOL_ALTROOT@Q})"
fi

DATASET_ROOT="$POOL/ROOT/$NAME"
DATASET_DATA="$POOL/DATA/$NAME"
DATASET_SCRATCH="$POOL/SCRATCH/$NAME"


#
# functions
#

print_header() {
    log "Target name:                     ${NAME@Q}"
    log "Target mountpoint:               ${MOUNTPOINT@Q}"
    log "Target pool:                     ${POOL@Q}"
    log "Target pool altroot:             $(<<<"${POOL_ALTROOT:+"${POOL_ALTROOT@Q}"}" print_or "(none)")"
    log "Target pool own mountpoint:      $(<<<"${POOL_MOUNTPOINT:+"${POOL_MOUNTPOINT@Q}"}" print_or "(none)")"
    log "Target users to create:          $(join ', ' "${USERS[@]@Q}" | print_or "(none)")"
    log "Target dataset options:          $(join ', ' "${OPTIONS[@]@Q}" | print_or "(none)")"
    log "Target dataset for OS:           ${DATASET_ROOT@Q}"
    log "Target dataset for user data:    ${DATASET_DATA@Q}"
    log "Target dataset for scratch data: ${DATASET_SCRATCH@Q}"
    read -r -s -n1 _
}

# $1: /path/a
# $2: /path/b
# Returns whether $2 is a descendant of $1
_path_beneath() {
    local parent="$1" child="$2"
    [[ $child && $parent && ( $child == "$parent" || $child == "${parent%%/}"/?* ) ]]
}

_do_mount() {
    local -
    set -x
    zfs mount -R "$1"
}
_do_unmount() {
    local -
    set -x
    ! mountpoint -q "$1" || umount -R "$1"
}
_do_destroy() {
    local -
    set -x
    zfs destroy -R "$@" ||:
}

pool_mount() {
    log "Mounting target hierarchy: ${DATASET_ROOT@Q}, ${DATASET_DATA@Q}, ${DATASET_SCRATCH@Q}"
    _do_mount "$DATASET_ROOT"
    _do_mount "$DATASET_DATA"
    _do_mount "$DATASET_SCRATCH"

    if _path_beneath "$MOUNTPOINT" "$POOL_MOUNTPOINT"; then
        log "Mounting pool own mountpoint: ${mp@Q}"
        # FIXME: mount only the protected parts,
        #        i.e. only those datasets whose mountpoints are descendants
        #        of the root dataset mountpoint (the one we unmounted before)
        _do_mount "$POOL"
    fi
}
pool_unmount() {
    local mp
    # 1. If pool's own mountpoint, aka root dataset mountpoint (e.g. /mnt/zfs/poolname)
    #    is beneath the target hierarchy mountpoint (e.g. / if we are deploying
    #    the primary OS on a newly-created pool under altroot), unmount the former
    #    to avoid overmounting
    if _path_beneath "$MOUNTPOINT" "$POOL_MOUNTPOINT"; then
        mp="$POOL_ALTROOT$POOL_MOUNTPOINT"
        log "Unmounting pool own mountpoint: ${mp@Q}"
        _do_unmount "$mp"
    fi
    # 2. Unmount hierarchy mountpoint itself
    mp="$POOL_ALTROOT$MOUNTPOINT"
    log "Unmounting target hierarchy: ${mp@Q}"
    _do_unmount "$mp"
}
pool_destroy_hierarchy() {
    log "Destroying target hierarchy: ${DATASET_ROOT@Q}, ${DATASET_DATA@Q}, ${DATASET_SCRATCH@Q}"
    _do_destroy "$DATASET_SCRATCH"
    _do_destroy "$DATASET_DATA"
    _do_destroy "$DATASET_ROOT"
}

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
        /?*) options+=( -o mountpoint="${MOUNTPOINT%%/}$mountpoint" ) ;;
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
        --os)      options+=( "${ZFS_OS_OPTIONS[@]}" ) ;;
        --big)     options+=( "${ZFS_BIG_OPTIONS[@]}" ) ;;
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

