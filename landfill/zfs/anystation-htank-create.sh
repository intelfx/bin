#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=./zfslib.sh
. "${BASH_SOURCE%/*}/zfslib.sh"


#
# definitions
#

POOL_NAME=htank
POOL_DEVICES=(
	        raidz  /dev/disk/by-id/dm-name-htank-{1,2,3,4}
	log            /dev/disk/by-id/dm-name-htank-log-1
	cache          /dev/disk/by-id/dm-name-htank-cache-1
	special mirror /dev/disk/by-id/dm-name-htank-special-{1,2}
)

POOL_CREATE_OPTS=(
	"${ZPOOL_CREATE_OPTS[@]}"
	-O compression=zstd-11  # 207 MiB/s (220 MiB/s)
	-O checksum=sha256
	# -O dedup=sha256

	-O recordsize=1M
	-O special_small_blocks=256K
)


#
# main
#

set -x

# zpool destroy "${POOL_NAME}" ||:
# blkdiscard -v -f "${POOL_DEVICES[@]}"
zpool create \
	"${POOL_CREATE_OPTS[@]}" \
	"${POOL_NAME}" -m /mnt/zfs/"${POOL_NAME}" -O canmount=off \
	"${POOL_DEVICES[@]}" \
	# EOL

zfs_allow_create "${POOL_NAME}" operator

par1 \
	zfs create -p ::: \
	"${POOL_NAME}"/DATA/{Archive,Backups,Files,Internal{,/{Bitcoin,Nextcloud}},Media,Public,Scratch,Torrents}
