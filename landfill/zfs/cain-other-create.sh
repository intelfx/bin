#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=./zfslib.sh
. "${BASH_SOURCE%/*}/zfslib.sh"
libsh_export_log

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

eval "$(globaltraps)"
set -x

zpool destroy "${POOL_NAME}" ||:
blkdiscard -v -f "${POOL_DEVICES[@]}"
zpool create \
	"${POOL_CREATE_OPTS[@]}" \
	"${POOL_NAME}" -m "/mnt/zfs/${POOL_NAME}" -O canmount=off \
	"${POOL_DEVICES[@]}" \
	# EOL

zfs_allow_create "${POOL_NAME}" intelfx

TEST_SIZE=100G
TEST_BS=(4k 16k 64k)
TEST_DATASET_ROOT="${POOL_NAME}/VM2"
TEST_MOUNTPOINT_ROOT="/srv/vm2"
TEST_ZVOL_ROOT="/dev/zvol/${TEST_DATASET_ROOT}"

zfs create -p \
	-o mountpoint="${TEST_MOUNTPOINT_ROOT}" \
	"${TEST_DATASET_ROOT}"

par1 zfs create -p \
	::: "${TEST_DATASET_ROOT}"/{img,qcow2,vol}

# Create test images
for bs in "${TEST_BS[@]}"; do
	# enclosing recordsize must be aligned with qcow2 _subcluster_ size, of which there are 32 per cluster
	QCOW2_CLUSTER_SIZE="$(bscalcq -k "${bs} * 32")k"

	par1 zfs create -p \
		-o recordsize="${bs}" \
		::: "${TEST_DATASET_ROOT}"/{img,qcow2}/"test-${bs}"
	zfs create -p \
		-V "${TEST_SIZE}" \
		-o volblocksize="${bs}" \
		"${TEST_DATASET_ROOT}/vol/test-${bs}"
	truncate -s "${TEST_SIZE}" \
		"${TEST_MOUNTPOINT_ROOT}/img/test-${bs}/file.img"
	qemu-img create -f qcow2 -o preallocation=off,extended_l2=on,cluster_size="${QCOW2_CLUSTER_SIZE}" \
		"${TEST_MOUNTPOINT_ROOT}/qcow2/test-${bs}/file.qcow2" "${TEST_SIZE}"
done
zfs snapshot -r "${TEST_DATASET_ROOT}@0"

# Partition test images
for bs in "${TEST_BS[@]}"; do
	ZVOL_PATH="${TEST_ZVOL_ROOT}/vol/test-${bs}"
	IMG_PATH="${TEST_MOUNTPOINT_ROOT}/img/test-${bs}/file.img"
	QCOW2_PATH="${TEST_MOUNTPOINT_ROOT}/qcow2/test-${bs}/file.qcow2"

	ss="$(blockdev --getss "${ZVOL_PATH}")"
	if (( ss != 4096 )); then
		die "Created zvol @ ${ZVOL_PATH@Q} is not 4Kn (sector size $ss, expected 4096), aborting -- check /sys/module/zfs/parameters/zvol_use_4kn"
	fi

	sgdisk \
		--new=1:0:0 \
		--typecode=1:0700 \
		--change-name=1:"test-vol-${bs}" \
		"${ZVOL_PATH}"

	# Partition raw image file via loopback device (this is the only way to enforce 4096-byte LBA)
	IMG_LOOP_PATH="$(
		losetup -Pf --show -b 4096 "${IMG_PATH}"
	)"
	ltrap "losetup -d ${IMG_LOOP_PATH@Q}"
	sgdisk \
		--new=1:0:0 \
		--typecode=1:0700 \
		--change-name=1:"test-img-${bs}" \
		"${IMG_LOOP_PATH}"
	lruntrap

	# Partition qcow2 by attaching it to a nbd device
	# NOTE: cannot use `qemu-nbd -c` because it lacks the option to set LBA size; serve and connect separately
	qemu-nbd \
		-k "${QCOW2_PATH}.sock" \
		--discard=unmap \
		--detect-zeroes=unmap \
		"${QCOW2_PATH}" & qemu_nbd_pid=$!
	sleep 0.1 # HACK
	nbd-client -unix "${QCOW2_PATH}.sock" /dev/nbd0 -b 4096
	ltrap "nbd-client -d /dev/nbd0; kill $qemu_nbd_pid"
	udevadm trigger --settle /dev/nbd0
	sgdisk \
		--new=1:0:0 \
		--typecode=1:0700 \
		--change-name=1:"test-qcow2-${bs}" \
		"/dev/nbd0"
	lruntrap
done
zfs snapshot -r "${TEST_DATASET_ROOT}@0part"

# Format test images
for bs in "${TEST_BS[@]}"; do
	ZVOL_PATH="${TEST_ZVOL_ROOT}/vol/test-${bs}"
	IMG_PATH="${TEST_MOUNTPOINT_ROOT}/img/test-${bs}/file.img"
	QCOW2_PATH="${TEST_MOUNTPOINT_ROOT}/qcow2/test-${bs}/file.qcow2"

	mkfs.ntfs -Q -c "$(bscalcq -b "${bs}")" -L "test-vol-${bs}" "/dev/disk/by-partlabel/test-vol-${bs}"

	# Format raw image file via loopback device (this is the only way to enforce 4096-byte LBA)
	IMG_LOOP_PATH="$(
		losetup -Pf --show -b 4096 "${IMG_PATH}"
	)"
	ltrap "losetup -d ${IMG_LOOP_PATH@Q}"
	mkfs.ntfs -Q -c "$(bscalcq -b "${bs}")" -L "test-img-${bs}" "/dev/disk/by-partlabel/test-img-${bs}"
	lruntrap

	# Format qcow2 by attaching it to a nbd device
	# NOTE: cannot use `qemu-nbd -c` because it lacks the option to set LBA size; serve and connect separately
	qemu-nbd \
		-k "${QCOW2_PATH}.sock" \
		--discard=unmap \
		--detect-zeroes=unmap \
		"${QCOW2_PATH}" & qemu_nbd_pid=$!
	sleep 0.1 # HACK
	nbd-client -unix "${QCOW2_PATH}.sock" /dev/nbd0 -b 4096
	ltrap "nbd-client -d /dev/nbd0; kill $qemu_nbd_pid"
	udevadm trigger --settle /dev/nbd0
	mkfs.ntfs -Q -c "$(bscalcq -b "${bs}")" -L "test-qcow2-${bs}" "/dev/disk/by-partlabel/test-qcow2-${bs}"
	lruntrap
done
zfs snapshot -r "${TEST_DATASET_ROOT}@fs"
