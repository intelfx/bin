#!/bin/bash

set -eo pipefail
shopt -s lastpipe

. lib.sh


#
# function
#

is_mountpoint() {
	[[ -d "$1" ]] || return 1
	mountpoint -q "$1"
}

is_mounted() {
	[[ -b "$1" ]] || return 1
	lsblk --nodeps --list --noheadings -o MOUNTPOINTS "$1" \
	| grep -q -vFx ''
}

_mtrace_do() {
	local -a cmd

	set -- "$@" ';'
	while (( $# )); do
		if [[ $1 != ';' ]]; then
			cmd+=("$1")
		elif (( ${#cmd[@]} )); then
			"${cmd[@]}" || return
			cmd=()
		fi
		shift
	done
}

_mtrace_log() {
	local -a lines cmd
	local msg

	set -- "$@" ';'
	while (( $# )); do
		if [[ $1 != ';' ]]; then
			cmd+=("$1")
		elif (( ${#cmd[@]} )); then
			lines+=("${cmd[*]@Q}")
			cmd=()
		fi
		shift
	done

	msg="[$(join '] + [' "${lines[@]}")]"
	_libsh_trace "$msg"
}

mtrace() {
	#local TIMEFORMAT=$'\nreal\t%3lR\nuser\t%3lU\nsys\t%3lS\ncpu\t%P%%\n'
	local TIMEFORMAT="== %3lR real  %3lU user  %3lS system  %P%% cpu"$'\n'
	_mtrace_log "$@"
	time _mtrace_do "$@"
}

mtraceq() {
	_mtrace_log "$@"
	_mtrace_do "$@"
	#say "== (not timed)"
}

aria2c() {
	command aria2c \
		--file-allocation=trunc \
		--enable-mmap=true \
		--allow-overwrite=true \
		--allow-piece-length-change=true \
		--auto-file-renaming=false \
		--conditional-get=true \
		--remote-time=true \
		--stderr=true \
		"$@"
}


#
# constants
#

declare -a TESTS=(
	ext4
	btrfs
	bcachefs
)
declare -A T_FSTYPE=(
	[ext4]=ext4
	[btrfs]=btrfs
	[bcachefs]=bcachefs
)
declare -A T_BLKDEV=(
	[ext4]=/dev/disk/by-partlabel/test1
	[btrfs]=/dev/disk/by-partlabel/test2
	[bcachefs]=/dev/disk/by-partlabel/test3
)
declare -A T_MOUNTPOINT=(
	[ext4]=/mnt/t-ext4
	[btrfs]=/mnt/t-btrfs
	[bcachefs]=/mnt/t-bcachefs
)
declare -A T_MKFSOPTS=(
	[ext4]="-m 0 -E lazy_itable_init=0,lazy_journal_init=0 -L test-ext4 -F"
	[btrfs]="--csum xxhash64 -L test-btrfs -f"
	[bcachefs]="--compression lz4 --discard -L test-bcachefs -f"
)
declare -A T_MNTOPTS=(
	[ext4]="noatime,discard"
	[btrfs]="noatime,compress=lzo,discard=async,flushoncommit"  # NOTE: flushoncommit is a pessimization
	[bcachefs]="noatime"
)

TEST_PAYLOAD_URL="https://ftp.mozilla.org/pub/firefox/releases/127.0b5/source/firefox-127.0b5.source.tar.xz"
unset TEST_PAYLOAD_FILE  # set in prepare_all()
TEST_PAYLOAD_DIR="/mnt/ram"
TEST_QUIESCE_TIME=10


#
# functions (2)
#

prepare_all() {
	local payname="${TEST_PAYLOAD_URL##*/}"
	local tstart tend tdeadline

	tstart="$(date +%s)"
	tdeadline="$(( tstart + TEST_QUIESCE_TIME ))"

	log "Unmounting and cleaning up directories"
	local dir
	for dir in "${T_MOUNTPOINT[@]}"; do
		if is_mountpoint "$dir"; then
			trace umount "$dir"
		fi
	done

	log "Unmounting and discarding block devices"
	local blkdev
	for blkdev in "${T_BLKDEV[@]}"; do
		[[ -b $blkdev ]] || die "Bad blkdev: $blkdev"
		if is_mounted "$blkdev"; then
			trace umount "$blkdev"
		fi
		trace blkdiscard -f "$blkdev"
	done

	log "Downloading $TEST_PAYLOAD_URL -> $TEST_PAYLOAD_DIR/$payname"
	trace aria2c "$TEST_PAYLOAD_URL" --dir "$TEST_PAYLOAD_DIR" --out "$payname"

	log "Decompressing $TEST_PAYLOAD_DIR/$payname"
	case "$payname" in
	*.xz) trace xz -d -k -f "$TEST_PAYLOAD_DIR/$payname"; TEST_PAYLOAD_FILE="${payname%.xz}";;
	*) TEST_PAYLOAD_FILE="$payname" ;;
	esac

	tend="$(date +%s)"
	if (( tend < tdeadline )); then
		local sleep="$(( tdeadline - tend ))"
		log "Sleeping for ${sleep}s to quiesce disks"
		sleep "$sleep"
	fi
}

run_one_test() {
	local id="$1"
	say
	loud "Running test ($id)"
	local LIBSH_LOG_PREFIX="${id^^}"

	local payload="$TEST_PAYLOAD_DIR/$TEST_PAYLOAD_FILE"
	[[ -f $payload ]] || die "Bad payload: $payload"

	local blkdev="${T_BLKDEV[$id]:?}"
	[[ -b $blkdev ]] || die "Bad blkdev: $blkdev"

	local fstype="${T_FSTYPE[$id]:?}"
	local mkfsopts="${T_MKFSOPTS[$id]:?}"

	# XXX: this trap goes into global context
	ltrap "trace blkdiscard -f '$blkdev'"
	eval "$(ltraps)"

	read -ra mkfs_args <<< "$mkfsopts"
	log "Creating $fstype on $blkdev ($mkfsopts)"
	trace "mkfs.$fstype" "${mkfs_args[@]}" "$blkdev"

	local mntpoint="${T_MOUNTPOINT[$id]:?}"
	local mntopts="${T_MNTOPTS[$id]:?}"
	log "Mounting $fstype on $blkdev to $mntpoint (${mntopts:-defaults})"
	ltrap "trace umount '$mntpoint'"
	trace mount --mkdir "$blkdev" "$mntpoint" -o "${mntopts:-defaults}"
	trace mkdir -p "$mntpoint"/{test1,test2}
	say

	local mntpayload="$mntpoint/${payload##*/}"
	log "#1: copying payload onto disk: $payload -> $mntpayload"
	mtraceq sync \; sysctl -q vm.drop_caches=3
	mtrace cp -a "$payload" -T "$mntpayload" \; sync

	log "#2: extracting payload from RAM: $payload -> $mntpoint/test1"
	mtraceq sync \; sysctl -q vm.drop_caches=3
	mtrace tar -xf "$payload" -C "$mntpoint/test1" \; sync

	log "#3: extracting payload from disk: $mntpayload -> $mntpoint/test2"
	mtraceq sync \; sysctl -q vm.drop_caches=3
	mtrace tar -xf "$mntpayload" -C "$mntpoint/test2" \; sync

	log "#4: archiving extracted payload into RAM"
	ltrap "rm -f '$TEST_PAYLOAD_DIR/dummy.tar'"
	mtraceq sync \; sysctl -q vm.drop_caches=3
	mtrace tar -cf "$TEST_PAYLOAD_DIR/dummy.tar" -C "$mntpoint/test1" . \; sync

	log "#5: archiving extracted payload onto disk"
	mtraceq sync \; sysctl -q vm.drop_caches=3
	mtrace tar -cf "$mntpoint/dummy.tar" -C "$mntpoint/test2" . \; sync

	log "Cleaning up"
}


#
# main
#

eval "$(globaltraps)"
prepare_all
run_one_test ext4
run_one_test btrfs
run_one_test bcachefs

log "Cleaning up"
