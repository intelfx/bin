#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=./zfslib.sh
. "${BASH_SOURCE%/*}/zfslib.sh"

#
# definitions
#

POOL_NAME=tank
POOL_DEVICES=(
	/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7PJNJ0L107220F_1
)
POOL_CREATE_OPTS=(
	"${ZPOOL_CREATE_OPTS[@]}"
	-O compression=zstd-1  # 5231 MiB/s (5143 MiB/s)
	-O checksum=sha256
)


#
# main
#

set -x

zpool destroy "${POOL_NAME}" ||:
blkdiscard -v -f "${POOL_DEVICES[@]}"
zpool create \
	"${POOL_CREATE_OPTS[@]}" \
	"${POOL_NAME}" -m "/mnt/zfs/${POOL_NAME}" -O canmount=off \
	"${POOL_DEVICES[@]}" \
	# EOL

zfs_allow_create "${POOL_NAME}" intelfx
