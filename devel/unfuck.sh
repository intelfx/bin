#!/bin/bash

set -eo pipefail
shopt -s lastpipe
set -x

if ! (( $# >= 1 )); then
	echo "Usage: $0 [major] [merge-script-args...]" >&2
	exit 1
fi

major="$1"
shift

case "$major" in
v5.18)
	~/bin/devel/merge_arch_and_pf.sh --major v5.18 "$@"
	git branch -f "build"

	#git checkout bcachefs/master
	#git revert 37744db6d21e3f463411ea696fae46295f2d8148
	#git rev-parse HEAD | read bcachefs
	bcachefs=e964adc844a80a98ddce62a2759ccd5596ec20d2

	git checkout --detach build
	git merge-repeatedly "$bcachefs"
	git cherry-pick 0e3d949b156e  # stacktrace: export stack_trace_save_tsk for bcachefs
	git cherry-pick a93110389b66  # LRNG - do not export add_bootloader_randomness()
	git cherry-pick e3d42e2d6d65  # lib: export errname for bcachefs
	git describe --tags --exact build | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch
	git branch -f "work/patch-$branch"
	git branch -f "work/patch-5.18"
	git branch -f "work/patch"
	;;
v5.19)
	~/bin/devel/merge_arch_and_pf.sh --major v5.19 "$@"
	git branch -f "build"

	git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

	git merge-repeatedly bcachefs/master
	#git cherry-pick fca6b6a74180  # mm/memcontrol.c: convert to printbuf, fix up merge
	#git cherry-pick 0e3d949b156e  # stacktrace: export stack_trace_save_tsk for bcachefs
	#git cherry-pick e3d42e2d6d65  # lib: export errname for bcachefs
	git branch -f "work/patch-$branch"
	git branch -f "work/patch-5.19"
	git branch -f "work/patch"
	;;
v6.0)
	~/bin/devel/merge_arch_and_pf.sh --major v6.0 "$@"
	git branch -f "build"

	git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

	git merge-repeatedly bcachefs/bcachefs-v6.0
	#git cherry-pick fca6b6a74180  # mm/memcontrol.c: convert to printbuf, fix up merge
	#git cherry-pick 0e3d949b156e  # stacktrace: export stack_trace_save_tsk for bcachefs
	#git cherry-pick e3d42e2d6d65  # lib: export errname for bcachefs
	#git cherry-pick 55fda0a14d3a  # mm: filemap: export mapping_seek_hole_data() for bcachefs
	git branch -f "work/patch-$branch"
	git branch -f "work/patch-6.0"
	git branch -f "work/patch"
	;;
v6.1)
	~/bin/devel/merge_arch_and_pf.sh --major v6.1 "$@"
	git branch -f "build"

	git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

	git merge-repeatedly bcachefs/master
	git branch -f "work/patch-$branch"
	git branch -f "work/patch-6.1"
	git branch -f "work/patch"
	;;
v6.2)
	~/bin/devel/merge_arch_and_pf.sh --major v6.2 "$@"
	git branch -f "build"

	git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

	#git merge-repeatedly --no-edit bcachefs/master
	#git revert --no-edit af2459558ef98998f9b8e55acac917ae7db649e2  # Delete seq_buf
	#git cherry-pick --no-edit 4b344b5f155ad0131f2add02ca7a06758c000a2b  # Fix up build for 6.1.9+pf4
	git branch -f "work/patch-$branch"
	git branch -f "work/patch-6.2"
	git branch -f "work/patch"
	;;
v6.3)
	~/bin/devel/merge_arch_and_pf.sh --major v6.3 "$@"
	git branch -f "build"

	git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

	#git merge-repeatedly --no-edit bcachefs/master
	#git revert --no-edit af2459558ef98998f9b8e55acac917ae7db649e2  # Delete seq_buf
	#git cherry-pick --no-edit 4b344b5f155ad0131f2add02ca7a06758c000a2b  # Fix up build for 6.1.9+pf4
	git branch -f "work/patch-$branch"
	git branch -f "work/patch-6.3"
	git branch -f "work/patch"
	;;
v6.4)
	~/bin/devel/merge_arch_and_pf.sh --major v6.4 "$@"
	git branch -f "build"

	git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

	export GIT_AUTHOR_DATE="@0 +0000" GIT_COMMITTER_DATE="@0 +0000"
	git merge-repeatedly --no-edit bcachefs/master
	#git cherry-pick --no-edit 616cf8265a8d40320df89e763956fa2c043b05c2  # accel/ivpu: deconflict ->alloc_pages() with same-named #define coming through bcachefs
	#git cherry-pick --no-edit 439a09791f0802a2b89db85cff831d511ed3547d  # mm: vmalloc: include gfp.h for alloc_hooks()

	git branch -f "work/patch-$branch"
	git branch -f "work/patch-6.4"
	git branch -f "work/patch"
	;;
v6.5)
	~/bin/devel/merge_arch_and_pf.sh --major v6.5 "$@"
	git branch -f "build"

	git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

	export GIT_AUTHOR_DATE="@0 +0000" GIT_COMMITTER_DATE="@0 +0000"
	git merge-repeatedly --no-edit bcachefs-hist/6.5

	git branch -f "work/patch-$branch"
	git branch -f "work/patch-6.5"
	git branch -f "work/patch"
	;;
v6.6)
	~/bin/devel/merge_arch_and_pf.sh --major v6.6 "$@"
	git branch -f "build"

	git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

	export GIT_AUTHOR_DATE="@0 +0000" GIT_COMMITTER_DATE="@0 +0000"
	git merge-repeatedly --no-edit bcachefs-hist/6.6

	git branch -f "work/patch-$branch"
	git branch -f "work/patch-6.6"
	git branch -f "work/patch"
	;;
v6.7)
	~/bin/devel/merge_arch_and_pf.sh --major v6.7 "$@"
	git branch -f "build"

	git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

	git branch -f "work/patch-$branch"
	git branch -f "work/patch-6.7"
	git branch -f "work/patch"
	;;
v6.8)
	~/bin/devel/merge_arch_and_pf.sh --major v6.8 "$@"
	git branch -f "build"

	git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

	git branch -f "work/patch-$branch"
	git branch -f "work/patch-6.8"
	git branch -f "work/patch"
	;;
*)
	echo "Unknown major: $major" >&2
	exit 1
	;;
esac
