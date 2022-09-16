set -eo pipefail
shopt -s lastpipe
set -x

~/bin/devel/merge_arch_and_pf.sh "$@"
git branch -f "build"

git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

git merge-repeatedly bcachefs/master
#git cherry-pick fca6b6a74180  # mm/memcontrol.c: convert to printbuf, fix up merge
#git cherry-pick 0e3d949b156e  # stacktrace: export stack_trace_save_tsk for bcachefs
#git cherry-pick e3d42e2d6d65  # lib: export errname for bcachefs
git branch -f "work/patch-$branch"
git branch -f "work/patch"

