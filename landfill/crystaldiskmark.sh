#!/bin/bash

log() {
	echo ":: $*" >&2
}

err() {
	echo "E: $*" >&2
}

die() {
	err "$@"
	exit 1
}

TARGET="$1"

if ! [[ -d "$TARGET" ]]; then
	die "Bad target: $TARGET"
fi

TARGET_FILE="$(mktemp -p "$TARGET" crystaldiskmark.XXX)"
trap "rm -vf '$TARGET_FILE'" EXIT

fio --loops=5 --size=1000m --filename="$TARGET_FILE" --stonewall --ioengine=libaio --direct=1 --iodepth=1 --fallocate=native \
	--name=Seq-Read-Q32 --bs=1m --iodepth=32 --rw=read \
	--name=Seq-Write-Q32 --bs=1m --iodepth=32 --rw=write \
	--name=Rand-Read-512K-Q32 --bs=512k --iodepth=32 --rw=randread \
	--name=Rand-Write-512K-Q32 --bs=512k --iodepth=32 --rw=randwrite \
	--name=Rand-Read-4K-Q32 --bs=4k --iodepth=32 --rw=randread \
	--name=Rand-Write-4K-Q32 --bs=4k --iodepth=32 --rw=randwrite \
	--name=Rand-Read-4K-Q8T8 --bs=4k  --iodepth=8 --numjobs=8 --rw=randread \
	--name=Rand-Write-4K-Q8T8 --bs=4k --iodepth=8 --numjobs=8 --rw=randwrite \
	--name=Rand-Read-4K-Q1 --bs=4k  --rw=randread \
	--name=Rand-Write-4K-Q1 --bs=4k --rw=randwrite \
