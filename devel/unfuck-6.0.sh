set -eo pipefail
shopt -s lastpipe
set -x

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

