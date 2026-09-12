#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=./zfslib.sh
. "${BASH_SOURCE%/*}/zfslib.sh"

#
# definitions
#

TANK_DEVICES=(
	/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7PJNJ0L107220F_1
)
TANK_CREATE_OPTS=(
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

# zpool destroy tank ||:
# blkdiscard -v -f "${TANK_DEVICES[@]}"
# zpool create \
#	"${TANK_CREATE_OPTS[@]}" \
#	tank -m /mnt/zfs/tank -O canmount=off \
#	"${TANK_DEVICES[@]}"

zfs_allow_create tank intelfx
