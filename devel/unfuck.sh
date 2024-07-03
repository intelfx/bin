#!/bin/bash

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
	[--lts]=ARG_LTS
	[--]=ARGS
)
parse_args _args "$@" || usage

case "${#ARGS[@]}" in
0) usage "expected 1 or more positional arguments" ;;
esac

ARG_MAJOR="${ARGS[1]}"
ARGS=( "${ARGS[@]:2}" )


#
# main
#

declare -A target
if [[ ${ARG_LTS+set} ]]; then
	shift
	target[build]=build-lts
else
	target[build]=build
	target[patch]=work/patch
fi

tag="v${ARG_MAJOR#v}"
major="${tag#v}"

export GIT_AUTHOR_DATE="@0 +0000" GIT_COMMITTER_DATE="@0 +0000"
~/bin/devel/merge_arch_and_pf.sh --major "$tag" "${ARGS[@]}"
if [[ ${target[build]+set} ]]; then
	git branch -f "${target[build]}"
fi

case "$tag" in
v5.18)
	bcachefs=e964adc844a80a98ddce62a2759ccd5596ec20d2
	git merge-repeatedly "$bcachefs"
	;;
v5.19|v6.[0-6])
	git merge-repeatedly "bcachefs-hist/$major"
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
esac

git describe --tags --exact build | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch
git branch -f "work/patch-${branch}"
git branch -f "work/patch-${major}"
if [[ ${target[patch]+set} ]]; then
	git branch -f "${target[patch]}"
fi
