#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=./zfscreatelib.sh
. "${BASH_SOURCE%/*}/zfscreatelib.sh"

#
# main
#

DATASET_ROOT="$POOL/ROOT/$NAME"
DATASET_DATA="$POOL/DATA/$NAME"
DATASET_SCRATCH="$POOL/SCRATCH/$NAME"

print_header

pool_unmount
pool_destroy_hierarchy

### "ROOT" ###
zfs_create --root   "ROOT"                                  "/"
zfs_create --os     "ROOT/usr"
zfs_create          "ROOT/var"
zfs_create          "ROOT/var/etc"                          "/etc"
zfs_create          "ROOT/var/log"
zfs_create          "ROOT/var/tmp"

### "DATA" ###
zfs_create --root   "DATA"                                  --nomount
zfs_create          "DATA/home"                             "/home"
zfs_create          "DATA/home/root"                        "/root"

### "SCRATCH" ###
zfs_create --root   "SCRATCH"                               --nomount
zfs_create --big    "SCRATCH/var-cache-pacman-pkg"          "/var/cache/pacman/pkg"                --global
zfs_create          "SCRATCH/scratch"                       "/mnt/scratch"                         --global
zfs_create          "SCRATCH/netdata"                       "/var/lib/netdata"
zfs_create          "SCRATCH/netdata/db"                    "/var/cache/netdata"
zfs_create_podman   "SCRATCH/containers/root"               "/var/lib/containers"
zfs_create_docker   "SCRATCH/docker/root"                   "/var/lib/docker"


zfs_create          "SCRATCH/srv-build"                     "/srv/build"
# zfs_create          "SCRATCH/srv-build/cache"
# zfs_create --os     "SCRATCH/srv-build/chroot"
# zfs_create --big    "SCRATCH/srv-build/src"
# zfs_create          "SCRATCH/srv-build/work"

### USERS ###
for user in "${USERS[@]}"; do
zfs_create          "SCRATCH/user/$user"                    "/home/$user/tmp/big"
zfs_create          "SCRATCH/cache/$user"                   "/home/$user/.cache"
zfs_create_podman   "SCRATCH/containers/$user"              "/home/$user/.local/share/containers"
done

pool_mount
