#!/bin/bash

set -eo pipefail
shopt -s lastpipe

. lib.sh || exit

#
# args & usage
#

_usage() {
	cat <<EOF
Usage: $0 [--lts] [MAJOR] [merge_arch_and_pf.sh args...]
EOF
}

declare -A _args=(
	[getopt]="+"
	[--lts]=ARG_LTS
	[--]=ARGS
)
parse_args _args "$@" || usage

case "${#ARGS[@]}" in
0) usage "expected 1 or more positional arguments" ;;
esac

ARG_MAJOR="${ARGS[0]}"
ARGS=( "${ARGS[@]:1}" )

#
# main
#

export GIT_AUTHOR_DATE="@0 +0000" GIT_COMMITTER_DATE="@0 +0000"

declare -A target
target[base_prefix]=base/base-
target[patch_prefix]=my/my-
if [[ ${ARG_LTS+set} ]]; then
	target[base]=base/lts
	target[patch]=my/lts
else
	target[base]=base/latest
	target[patch]=my/latest
fi

tag="v${ARG_MAJOR#v}"
major="${tag#v}"

Trace ~/bin/devel/merge_arch_and_pf.sh --major "$tag" "${ARGS[@]}"
Trace git describe --tags --exact HEAD \
	| grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' \
	| IFS= read -r minor

Trace git branch -f "${target[base_prefix]}${major}"
Trace git branch -f "${target[base_prefix]}${minor}"
Trace git branch -f "${target[base]}"

function make_merge() {
	Trace git merge-repeatedly --ff --no-edit "$@"
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
esac

Trace git branch -f "${target[patch_prefix]}${minor}"
Trace git branch -f "${target[patch_prefix]}${major}"
Trace git branch -f "${target[patch]}"
