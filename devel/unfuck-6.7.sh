set -eo pipefail
shopt -s lastpipe
set -x

~/bin/devel/merge_arch_and_pf.sh --major v6.7 "$@"
git branch -f "build"

git describe --tags --exact | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch

git branch -f "work/patch-$branch"
git branch -f "work/patch-6.7"
git branch -f "work/patch"
