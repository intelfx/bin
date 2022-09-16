#!/bin/bash

set -eo pipefail
shopt -s lastpipe
set -x

~/bin/devel/merge_arch_and_pf.sh
git branch -f "build"

git checkout bcachefs/master
git revert 37744db6d21e3f463411ea696fae46295f2d8148
git rev-parse HEAD | read bcachefs

git checkout --detach build
git merge-repeatedly "$bcachefs"
git cherry-pick 0e3d949b156e  # stacktrace: export stack_trace_save_tsk for bcachefs
git cherry-pick a93110389b66  # LRNG - do not export add_bootloader_randomness()
git cherry-pick e3d42e2d6d65  # lib: export errname for bcachefs
git describe --tags --exact build | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | read branch
git branch -f "work/patch-$branch"
git branch -f "work/patch"
