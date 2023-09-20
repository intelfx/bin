set -eo pipefail
shopt -s lastpipe
set -x

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

