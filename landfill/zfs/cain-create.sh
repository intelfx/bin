#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=./zfslib.sh
. "${BASH_SOURCE%/*}/zfslib.sh"

#
# definitions
#

BPOOL_NAME=bpool
BPOOL_DEVICES=(
	/dev/disk/by-partlabel/cain-XBOOTLDR
)
BPOOL_CREATE_OPTS=(
	-o compatibility=grub2
	"${ZPOOL_CREATE_OPTS_ESSENTIAL[@]}"
	-O dnodesize=legacy # -O xattr=sa -O acltype=posixacl
	-O compression=lz4
	-O checksum=sha256
)

RPOOL_NAME=rpool
RPOOL_DEVICES=(
	/dev/disk/by-id/dm-name-cain-rpool-1
)
RPOOL_CREATE_OPTS=(
	"${ZPOOL_CREATE_OPTS[@]}"
	-O compression=zstd-1  # 5231 MiB/s (5143 MiB/s)
	-O checksum=sha256
)


#
# main
#

set -x

zpool destroy "${BPOOL_NAME}" ||:
blkdiscard -v -f "${BPOOL_DEVICES[@]}"
zpool create \
	"${BPOOL_CREATE_OPTS[@]}" \
	"${BPOOL_NAME}" -R /target -m "/mnt/zfs/${BPOOL_NAME}" -O canmount=off \
	"${BPOOL_DEVICES[@]}" \
	# EOL

zfs_allow_create "${BPOOL_NAME}" operator

zpool destroy "${RPOOL_NAME}" ||:
blkdiscard -v -f "${RPOOL_DEVICES[@]}"
zpool create \
	"${RPOOL_CREATE_OPTS[@]}" \
	"${RPOOL_NAME}" -R /target -m "/mnt/zfs/${RPOOL_NAME}" -O canmount=off \
	"${RPOOL_DEVICES[@]}"

zfs_allow_create "${RPOOL_NAME}" operator

zfs create -u \
	-o canmount=off \
	"${BPOOL_NAME}"/BOOT
zfs create -u \
	-o mountpoint=/boot \
	"${BPOOL_NAME}"/BOOT/arch
