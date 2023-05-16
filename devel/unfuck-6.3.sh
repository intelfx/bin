set -eo pipefail
shopt -s lastpipe
set -x

~/bin/devel/merge_arch_and_pf.sh --major v6.3 "$@"
git branch -f "build"

git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

#git merge-repeatedly --no-edit bcachefs/master
#git revert --no-edit af2459558ef98998f9b8e55acac917ae7db649e2  # Delete seq_buf
#git cherry-pick --no-edit 4b344b5f155ad0131f2add02ca7a06758c000a2b  # Fix up build for 6.1.9+pf4
git branch -f "work/patch-$branch"
git branch -f "work/patch-6.3"
git branch -f "work/patch"

