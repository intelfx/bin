#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=../lib/lib.sh
. lib.sh

#
# args & usage
#

_usage() {
	cat <<EOF
Usage: $0 [--lts | -n[NAME] | --name[=NAME]] [MAJOR] [merge_arch_and_pf.sh args...]

Options:
	--lts			Prefix branch name with "lts-"
	-n, -name[=NAME]	Prefix branch name with "NAME-"
				(if empty, do not create a named branch)
	-d, --dir[=DIR]		Kernel source directory (default: \$HOME/devel/ext/linux or variants)
	--aarch64, --arm64	HACK: use aarch64-specific branches
	--armv7, --arm		HACK: use armv7-specific branches
EOF
}

declare -A _args=(
	[getopt]="+"
	[--lts]=ARG_LTS
	['-n|--name::']="ARG_NAME default="
	['-d|--dir:']=ARG_KERNEL_DIR
	['--aarch64|--arm64']=ARG_ARM64
	['--armv7|--arm']=ARG_ARM32
	['--rpi']=ARG_RPI
	[--]=ARGS
)
parse_args _args "$@" || usage

case "${#ARGS[@]}" in
0) usage "expected 1 or more positional arguments" ;;
esac

if [[ ${ARG_LTS+set} && ${ARG_NAME+set} ]]; then
	usage "--name and --lts cannot be used together"
fi

if (( ARG_ARM32 + ARG_ARM64 > 1 )); then
	die "--arm/--armv7 and --arm64/--aarch64 are mutually exclusive"
fi

ARG_MAJOR="${ARGS[0]}"
ARGS=( "${ARGS[@]:1}" )

unset KERNEL_DIR
if [[ ${ARG_KERNEL_DIR+set} ]]; then
	KERNEL_DIR="$ARG_KERNEL_DIR"
fi

KERNEL_TRY_DIRS=()

# HACK: ZFS configuration (zfs_config.h) is checked into the repo, and it is not arch-invariant
ZFS_BRANCH_SUFFIX=
TARGET_BRANCH_SUFFIX=
if [[ ${ARG_ARM64+set} ]]; then
	ZFS_BRANCH_SUFFIX=-aarch64
	TARGET_BRANCH_SUFFIX=-aarch64
	NAMED_BRANCH_SUFFIX=-aarch64
	KERNEL_TRY_DIRS+=(
		"$HOME/devel/tmp/linux-aarch64"
	)
elif [[ ${ARG_ARM32+set} ]]; then
	ZFS_BRANCH_SUFFIX=-armv7
	TARGET_BRANCH_SUFFIX=-armv7
	NAMED_BRANCH_SUFFIX=-armv7
	KERNEL_TRY_DIRS+=(
		"$HOME/devel/tmp/linux-armv7"
	)
fi

if [[ ${ARG_RPI+set} ]]; then
	if ! (( ARG_ARM64 + ARG_ARM32 )); then
		die "--rpi without --arm{,64}; are you daft?"
	fi
	TARGET_BRANCH_SUFFIX="-rpi$TARGET_BRANCH_SUFFIX"
	NAMED_BRANCH_SUFFIX="-rpi$NAMED_BRANCH_SUFFIX"
	if ! [[ $ARG_NAME ]]; then
		ARG_NAME=rpi
	fi
	if [[ $ARG_NAME == *rpi* ]]; then
		NAMED_BRANCH_SUFFIX="${NAMED_BRANCH_SUFFIX#-rpi}"
	fi
fi

#
# main
#

export GIT_AUTHOR_DATE="@0 +0000" GIT_COMMITTER_DATE="@0 +0000"

tag="v${ARG_MAJOR#v}"
major="${tag#v}"

if ! [[ ${KERNEL_DIR+set} ]]; then
	KERNEL_TRY_DIRS+=(
		"$HOME/devel/ext/linux-$major"
		"$HOME/devel/ext/linux"
	)
	for KERNEL_DIR in "${KERNEL_TRY_DIRS[@]}"; do
		if [[ -d "$KERNEL_DIR" ]]; then
			break
		fi
	done
fi
KERNEL_TOPLEVEL="$(git -C "$KERNEL_DIR" rev-parse --show-toplevel)" \
	&& [[ $KERNEL_TOPLEVEL ]] \
	|| die "Invalid kernel directory: ${KERNEL_DIR@Q}"
Trace cd "$KERNEL_TOPLEVEL"

declare -A target
target[base_prefix]=base/base-
target[patch_prefix]=my/my$TARGET_BRANCH_SUFFIX-
if [[ $ARG_NAME ]]; then
	target[base]=base/$ARG_NAME
	target[patch]=my/$ARG_NAME$NAMED_BRANCH_SUFFIX
	log "Using named branches: {base,my}/${target[patch]##*/}"
elif [[ ${ARG_NAME+set} ]]; then
	:
	log "Not using named branches"
elif [[ ${ARG_LTS+set} ]]; then
	target[base]=base/lts
	target[patch]=my/lts$NAMED_BRANCH_SUFFIX
	log "Using \"lts\" branches: .../${target[patch]##*/}"
else
	target[base]=base/latest
	target[patch]=my/latest$NAMED_BRANCH_SUFFIX
	log "Using \"latest\" branches: .../${target[patch]##*/}"
fi

Trace ~/bin/devel/merge_arch_and_pf.sh --major "$tag" "${ARGS[@]}"
Trace git describe --tags --exact HEAD \
	| grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' \
	| IFS= read -r minor

Trace git branch -f "${target[base_prefix]}${major}"
Trace git branch -f "${target[base_prefix]}${minor}"
if [[ ${target[base]} ]]; then
	Trace git branch -f "${target[base]}"
fi

function make_merge() {
	local -a branches
	local arg varname branchname
	for arg; do
		IFS='=' read -r varname branchname <<<"$arg"
		if [[ $varname && $branchname ]]; then
			if [[ ${!varname+set} ]]; then
				log "Applying: ${branchname@Q} (${varname}=1)"
				branches+=("$branchname")
			fi
		else
			branches+=("$arg")
		fi
	done

	Trace git merge-repeatedly --ff --no-edit "${branches[@]}"
}

case "$tag" in
v5.18)
	make_merge \
		e964adc844a80a98ddce62a2759ccd5596ec20d2
	;;
v5.19|v6.[0-5])
	make_merge \
	       "bcachefs-hist/$major"
	;;
v6.6)
	make_merge \
		work/minmax-${major}
	make_merge \
		bcachefs/${major}
	;;
esac

case "$tag" in
v5.18)
	git cherry-pick 0e3d949b156e  # stacktrace: export stack_trace_save_tsk for bcachefs
	git cherry-pick a93110389b66  # LRNG - do not export add_bootloader_randomness()
	git cherry-pick e3d42e2d6d65  # lib: export errname for bcachefs
	;;
v5.19)
	#git cherry-pick fca6b6a74180  # mm/memcontrol.c: convert to printbuf, fix up merge
	#git cherry-pick 0e3d949b156e  # stacktrace: export stack_trace_save_tsk for bcachefs
	#git cherry-pick e3d42e2d6d65  # lib: export errname for bcachefs
	;;
v6.0)
	#git cherry-pick fca6b6a74180  # mm/memcontrol.c: convert to printbuf, fix up merge
	#git cherry-pick 0e3d949b156e  # stacktrace: export stack_trace_save_tsk for bcachefs
	#git cherry-pick e3d42e2d6d65  # lib: export errname for bcachefs
	#git cherry-pick 55fda0a14d3a  # mm: filemap: export mapping_seek_hole_data() for bcachefs
	;;
v6.2)
	#git revert --no-edit af2459558ef98998f9b8e55acac917ae7db649e2  # Delete seq_buf
	#git cherry-pick --no-edit 4b344b5f155ad0131f2add02ca7a06758c000a2b  # Fix up build for 6.1.9+pf4
	;;
v6.3)
	#git revert --no-edit af2459558ef98998f9b8e55acac917ae7db649e2  # Delete seq_buf
	#git cherry-pick --no-edit 4b344b5f155ad0131f2add02ca7a06758c000a2b  # Fix up build for 6.1.9+pf4
	;;
v6.4)
	#git cherry-pick --no-edit 616cf8265a8d40320df89e763956fa2c043b05c2  # accel/ivpu: deconflict ->alloc_pages() with same-named #define coming through bcachefs
	#git cherry-pick --no-edit 439a09791f0802a2b89db85cff831d511ed3547d  # mm: vmalloc: include gfp.h for alloc_hooks()
	;;

	# historical branches
	# make_merge \
		#work/btrfs-6.10 \
		#work/btrfs-metadata-fix-v1r3-6.7 \
		#work/amd-prefcore-v9-6.5 \
		#work/gvt-vfio-locking-6.1 \
		#work/amd-pstate-epp-6.1 \
		#work/bcachefs-zstd-5.15 \
		#work/amd-pstate-5.15-v4 \  # in -pf
		#work/btrfs-read-policy \
		#work/amd-energy-support-all-cpus-5.13 \  # superseded
		#work/amd-energy-restore-permissions-5.12 \  # superseded
		#work/no-udp-tso-5.9 \  # fixed
		#work/hid-logitech-mx-master-3 \  # merged
		#work/pci-reenable-aspm \  # merged
		#work/acpi-turn-off-5.11 \  # merged
		#bcachefs/5.5 \
		#work/cve-2019-14615-revert-5.5 \
		#work/bug112315-i915-kbl-rc6-5.4 \
		#work/bug111594-i915-guc-rc6-5.4 \

v6.6)
	# conflicts
	make_merge \
		work/i915-fastboot-revert-6.6
	make_merge \
		work/em7565-ids-6.6
	# main
	make_merge \
		work/iwlwifi-lar-v2-6.6 \
		work/amd-energy-6.6 \
		work/btrfs-remove-ghost-subvolume-6.6 \
		work/btrfs-allocation-hint-6.6 \
		work/tsc-directsync-6.6 \
		work/no-jobserver-exec-6.6 \
		work/gvt-failsafe-6.6 \
		work/gvt-workaround-6.6 \
		work/i915-fastboot-revert-6.6 \
		work/kbuild-6.6 \
		work/em7565-ids-6.6 \
		work/cddl-6.6 \
		work/zfs-6.6 \
	;;
v6.11)
	# conflicts
	make_merge \
		work/em7565-ids-6.10
	# main
	make_merge \
		work/iwlwifi-lar-v2-6.10 \
		work/amd-energy-6.11 \
		work/btrfs-remove-ghost-subvolume-6.10 \
		work/btrfs-allocation-hint-6.10 \
		work/tsc-directsync-6.10 \
		work/no-jobserver-exec-6.10 \
		work/gvt-failsafe-6.10 \
		work/gvt-workaround-6.10 \
		work/i915-fastboot-revert-6.10 \
		work/kbuild-6.10 \
		work/em7565-ids-6.10 \
		work/zswap-writeback-6.11 \
		work/acpi-osc-6.11 \
		work/fs-6.11 \
		work/cddl-6.11 \
		work/zfs-6.11 \
	;;

v6.12)
	# main
	make_merge \
		work/iwlwifi-lar-v2-6.12 \
		work/amd-energy-6.12 \
		work/btrfs-remove-ghost-subvolume-6.12 \
		work/btrfs-allocation-hint-6.12 \
		work/tsc-directsync-6.12 \
		work/no-jobserver-exec-6.12 \
		work/kbuild-6.12 \
		work/em7565-ids-6.12 \
		work/zswap-writeback-6.12 \
		work/acpi-osc-6.12 \
		work/fs-6.12-noop \
		work/cddl-6.12 \
		work/zfs-6.12 \
		work/fonts-6.12 \
		work/cpupower-6.12 \
		work/pf-no-teo-6.12 \
		# work/gvt-failsafe-6.12 \
		# work/gvt-workaround-6.12 \
		# work/i915-fastboot-revert-6.12 \
	;;

v6.13)
	# main
	make_merge \
		work/iwlwifi-lar-v2-6.12 \
		work/amd-energy-6.12 \
		work/btrfs-remove-ghost-subvolume-6.12 \
		work/btrfs-allocation-hint-6.12 \
		work/tsc-directsync-6.12 \
		work/no-jobserver-exec-6.12 \
		work/kbuild-6.12 \
		work/em7565-ids-6.12 \
		work/zswap-writeback-6.12 \
		work/acpi-osc-6.12 \
		work/fs-6.13-noop \
		work/cddl-6.12 \
		work/zfs-6.12 \
		work/cpupower-6.12 \
		# work/gvt-failsafe-6.12 \
		# work/gvt-workaround-6.12 \
		# work/i915-fastboot-revert-6.13 \
	;;

v6.14)
	# main
	make_merge \
		work/iwlwifi-lar-v2-6.12 \
		work/amd-energy-6.12 \
		work/btrfs-remove-ghost-subvolume-6.12 \
		work/btrfs-allocation-hint-6.12 \
		work/tsc-directsync-6.12 \
		work/no-jobserver-exec-6.12 \
		work/kbuild-6.12 \
		work/em7565-ids-6.12 \
		work/zswap-writeback-6.12 \
		work/acpi-osc-6.12 \
		work/fs-6.14-noop \
		work/cddl-6.12 \
		work/zfs-6.14 \
		work/cpupower-6.12 \
		# work/gvt-failsafe-6.12 \
		# work/gvt-workaround-6.12 \
		# work/i915-fastboot-revert-6.14 \
	;;

v6.15)
	# main
	make_merge \
		work/iwlwifi-lar-v2-6.12 \
		work/amd-energy-6.12 \
		work/btrfs-remove-ghost-subvolume-6.12 \
		work/btrfs-allocation-hint-6.12 \
		work/tsc-directsync-6.12 \
		work/no-jobserver-exec-6.12 \
		work/kbuild-6.12 \
		work/em7565-ids-6.12 \
		work/zswap-writeback-6.12 \
		work/acpi-osc-6.12 \
		work/fs-6.15pf-noop \
		work/cddl-6.15 \
		work/zfs-6.15 \
		work/pf-no-teo-6.15 \
		work/logitech-hidpp-6.15 \
		# work/gvt-failsafe-6.12 \
		# work/gvt-workaround-6.12 \
		# work/i915-fastboot-revert-6.15 \
	;;

v6.16)
	# main
	make_merge \
		work/iwlwifi-lar-v2-6.12 \
		work/amd-energy-6.16 \
		work/btrfs-remove-ghost-subvolume-6.12 \
		work/btrfs-allocation-hint-6.12 \
		work/tsc-directsync-6.16 \
		work/no-jobserver-exec-6.12 \
		work/kbuild-6.12 \
		work/em7565-ids-6.12 \
		work/zswap-writeback-6.12 \
		work/acpi-osc-6.12 \
		work/logitech-hidpp-6.16 \
		work/fs-6.16-noop \
		work/cddl-6.16 \
		work/zfs-6.16 \
		work/pf-no-teo-6.16 \
		# work/gvt-failsafe-6.12 \
		# work/gvt-workaround-6.12 \
		# work/i915-fastboot-revert-6.15 \
	;;

v6.17)
	# bcachefs
	make_merge \
		work/bcachefs-6.17 \
		"$(git describe --tags --match 'bcachefs/*' --exact-match --always bcachefs-tools/release)" \
		# EOL

	# main
	make_merge \
		work/iwlwifi-lar-v3-6.17 \
		work/amd-energy-6.16 \
		work/btrfs-remove-ghost-subvolume-6.12 \
		work/btrfs-allocation-hint-6.12 \
		work/tsc-directsync-6.16 \
		work/no-jobserver-exec-6.12 \
		work/kbuild-6.12 \
		work/em7565-ids-6.12 \
		work/zswap-writeback-6.12 \
		work/acpi-osc-6.12 \
		work/logitech-hidpp-6.16 \
		work/fs-6.17-noop \
		work/cddl-6.17 \
		work/zfs-6.17 \
		work/fonts-6.17 \
		work/intel-rapl-hack-6.17 \
		work/pf-no-teo-6.17 \
		work/pf-no-archlinux-6.17 \
		# work/gvt-failsafe-6.12 \
		# work/gvt-workaround-6.12 \
		# work/i915-fastboot-revert-6.15 \
	;;

v6.18)
	if [[ ${ARG_RPI+set} ]]; then
		make_merge \
			raspberrypi/rpi-6.18.y \
			pikvm/pikvm-6.18 \
			# EOL
	fi

	# main
	make_merge \
		work/bcachefs-6.18 \
		"$(git describe --tags --match 'bcachefs/*' --exact-match --always bcachefs-tools/release)" \
		work/iwlwifi-lar-v3-6.18 \
		work/amd-energy-6.18 \
		work/btrfs-remove-ghost-subvolume-6.18 \
		work/btrfs-allocation-hint-6.18 \
		work/tsc-directsync-6.18 \
		work/no-jobserver-exec-6.18 \
		work/kbuild-6.18 \
		work/em7565-ids-6.18 \
		work/zswap-writeback-6.18 \
		work/acpi-osc-6.18 \
		work/logitech-hidpp-6.18.15 \
		work/fs-6.18 \
		work/cddl-6.18 \
		work/zfs-6.18$ZFS_BRANCH_SUFFIX \
		work/fonts-6.18 \
		work/intel-rapl-hack-6.18 \
		work/pf-no-teo-6.18 \
		work/perf-zstd-6.18.52 \
		work/mitigations-6.18 \
		ARG_ARM32=work/arm-ioport-map-6.18 \
		ARG_RPI=work/rpi-6.18 \
		# work/gvt-failsafe-6.18 \
		# work/gvt-workaround-6.18 \
		# work/i915-fastboot-revert-6.18 \
	;;

v6.19)
	# bcachefs
	make_merge \
		work/bcachefs-6.18 \
		"$(git describe --tags --match 'bcachefs/*' --exact-match --always bcachefs-tools/release)" \
		# EOL

	# main
	make_merge \
		work/iwlwifi-lar-v3-6.18 \
		work/amd-energy-6.18 \
		work/btrfs-remove-ghost-subvolume-6.18 \
		work/btrfs-allocation-hint-6.18 \
		work/tsc-directsync-6.18 \
		work/no-jobserver-exec-6.19 \
		work/kbuild-6.18 \
		work/em7565-ids-6.18 \
		work/zswap-writeback-6.18 \
		work/acpi-osc-6.18 \
		work/logitech-hidpp-6.19 \
		work/fs-6.18-noop \
		work/cddl-6.19 \
		work/zfs-6.19 \
		work/fonts-6.19 \
		work/intel-rapl-hack-6.18 \
		work/pf-no-teo-6.19 \
		work/perf-zstd-6.18 \
		work/mitigations-6.18 \
		# work/gvt-failsafe-6.18 \
		# work/gvt-workaround-6.18 \
		# work/i915-fastboot-revert-6.18 \
	;;

v7.0)
	# bcachefs
	make_merge \
		work/bcachefs-6.18 \
		"$(git describe --tags --match 'bcachefs/*' --exact-match --always bcachefs-tools/release)" \
		# EOL

	# main
	make_merge \
		work/iwlwifi-lar-v3-7.0 \
		work/amd-energy-6.18 \
		work/btrfs-remove-ghost-subvolume-7.0 \
		work/btrfs-allocation-hint-7.0 \
		work/tsc-directsync-6.18 \
		work/no-jobserver-exec-6.19 \
		work/kbuild-6.18 \
		work/em7565-ids-6.18 \
		work/zswap-writeback-6.18 \
		work/acpi-osc-7.0 \
		work/logitech-hidpp-6.19 \
		work/fs-6.18-noop \
		work/cddl-7.0 \
		work/zfs-7.0 \
		work/fonts-6.19 \
		work/intel-rapl-hack-6.18 \
		work/pf-no-teo-7.0 \
		work/perf-zstd-6.18 \
		work/mitigations-7.0 \
		# work/gvt-failsafe-6.18 \
		# work/gvt-workaround-6.18 \
		# work/i915-fastboot-revert-6.18 \
	;;

v7.1)
	if [[ ${ARG_RPI+set} ]]; then
		make_merge \
			raspberrypi/rpi-7.1.y \
			pikvm/pikvm-7.1 \
			# EOL
	fi

	# main
	make_merge \
		work/bcachefs-7.1 \
		"$(git describe --tags --match 'bcachefs/*' --exact-match --always bcachefs-tools/release)" \
		work/iwlwifi-lar-v3-7.0 \
		work/amd-energy-6.18 \
		work/btrfs-remove-ghost-subvolume-7.0 \
		work/btrfs-allocation-hint-7.0 \
		work/tsc-directsync-7.1 \
		work/no-jobserver-exec-6.19 \
		work/kbuild-6.18 \
		work/em7565-ids-6.18 \
		work/zswap-writeback-6.18 \
		work/acpi-osc-7.0 \
		work/logitech-hidpp-6.19 \
		work/fs-6.18 \
		work/cddl-7.1 \
		work/zfs-7.1$ZFS_BRANCH_SUFFIX \
		work/fonts-7.1 \
		work/intel-rapl-hack-6.18 \
		work/pf-no-teo-7.0 \
		work/perf-zstd-7.1 \
		work/mitigations-7.0 \
		work/thinkpad-ucsi-7.1.12 \
		ARG_ARM32=work/arm-ioport-map-6.18 \
		ARG_RPI=work/rpi-7.1 \
		# work/gvt-failsafe-6.18 \
		# work/gvt-workaround-6.18 \
		# work/i915-fastboot-revert-6.18 \
	;;
esac

Trace git branch -f "${target[patch_prefix]}${minor}"
Trace git branch -f "${target[patch_prefix]}${major}"
if [[ ${target[patch]} ]]; then
	Trace git branch -f "${target[patch]}"
fi
