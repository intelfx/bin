set -eo pipefail
shopt -s lastpipe
set -x

~/bin/devel/merge_arch_and_pf.sh --major v6.5 "$@"
git branch -f "build"

git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

export GIT_AUTHOR_DATE="@0 +0000" GIT_COMMITTER_DATE="@0 +0000"
git merge-repeatedly --no-edit bcachefs/master

git branch -f "work/patch-$branch"
git branch -f "work/patch-6.5"
git branch -f "work/patch"
