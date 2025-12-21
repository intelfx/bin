#!/bin/bash

set -e
. ${BASH_SOURCE%/*}/zfscreatelib.sh


#
# main
#

DATASET_ROOT="$POOL/ROOT/$NAME"
DATASET_DATA="$POOL/DATA/$NAME"
DATASET_SCRATCH="$POOL/SCRATCH/$NAME"

print_header

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
zfs_create          "DATA/home"                             "/home"
zfs_create          "DATA/home/root"                        "/root"

### "SCRATCH" ###
zfs_create --root   "SCRATCH"                               --nomount
zfs_create          "SCRATCH/netdata"                       "/var/lib/netdata"
zfs_create          "SCRATCH/netdata/db"                    "/var/cache/netdata"
zfs_create_podman   "SCRATCH/containers/root"               "/var/lib/containers"
zfs_create_docker   "SCRATCH/docker/root"                   "/var/lib/docker"

if [[ $NAME == anystation ]]; then
zfs_create          "SCRATCH/scratch"                                                              --global
zfs_create          "SCRATCH/scratch/big"                                                          --global
zfs_create          "SCRATCH/scratch/borg"                                                         --global
zfs_create          "SCRATCH/scratch/cache"                                                        --global
zfs_create --big    "SCRATCH/var-cache-pacman-pkg"          --nomount                              --global
zfs_create          "SCRATCH/var-cache-pacman-pkg/arch"                                            --global
zfs_create          "SCRATCH/var-cache-pacman-pkg/steamos"                                         --global
zfs_create          "SCRATCH/machines"                      "/var/lib/machines"
zfs_create          "SCRATCH/libvirt"                       "/var/lib/libvirt"
zfs_create          "SCRATCH/incus"                         "/var/lib/incus"
zfs_create          "SCRATCH/k3s"                           "/var/lib/rancher/k3s"
zfs_create          "SCRATCH/kubelet"                       "/var/lib/kubelet"
fi

if [[ $NAME == stratofortress ]]; then
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
zfs_create_podman   "SCRATCH/containers/$user"              "/home/$user/.local/share/containers"
done

set -x

# zfs mount -R "$DATASET_ROOT"
# zfs mount -R "$DATASET_DATA"
# zfs mount -R "$DATASET_SCRATCH"

{ set +x; } &>/dev/null
