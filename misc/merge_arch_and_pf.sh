#!/bin/bash

set -eo pipefail
shopt -s lastpipe

. lib.sh || exit

log "Fetching remotes"
git fetch -j$(nproc) --multiple stable arch pf

log "Determining versions"
tag="$(git describe --match 'v*.*.*' --abbrev=0 stable/linux-rolling-stable)"
log " Latest stable: $tag"
arch_tag="$(git tag --list "$tag-arch*" | sed -nr 's|^.*-arch([0-9]+)$|\1\t\0|p' | sort -k1 -n | cut -f2 | tail -n1)"
log " Latest -arch tag: $arch_tag"
release="$(<<<"$tag" sed -nr 's|^v([0-9]+\.[0-9]+)\.[0-9]+$|\1|p')"
log " Major release: $release"

if ! [[ $tag && $arch_tag && $release ]]; then
	die "Failed to parse tags / determine versions"
fi

eval "$(globaltraps)"

log "Merging -pf"
git checkout -f "$arch_tag"
if ! git merge --no-commit "pf/pf-$release"; then
	ltrap 'git merge --abort'
fi

git_list_conflicts() {
	git status --untracked=no --porcelain | { grep -E '^(AA|DD|.U|U.) ' || true; }
}

git_list_unstaged() {
	git status  --untracked=no --porcelain | { grep -E '^.[^ ] ' || true; }
}

git_list_parse() {
	local line="$1"
	index="${line:0:1}"
	worktree="${line:1:1}"
	file="${line:3}"
}

makefile_get_extraversion() {
	<Makefile sed -nr 's|^EXTRAVERSION = -([^ ]+)$|\1|p' | head -n1
}

merge_makefile() {
	local pf_extraversion ours_extraversion

	git checkout --theirs Makefile
	if ! pf_extraversion="$(makefile_get_extraversion)"; then
		die "Could not parse -pf EXTRAVERSION"
	fi

	if ! ours_extraversion="$(makefile_get_extraversion)"; then
		die "Could not parse main EXTRAVERSION"
	fi

	sed -r "s|^(EXTRAVERSION = ).*$|\1$ours_extraversion$pf_extraversion|" -i Makefile
	git add Makefile
}

log "Handling conflicts"
git_list_conflicts | while read line; do
	git_list_parse "$line"
	case "$file" in
	Makefile)
		merge_makefile
		;;
	*)
		die "Do not know how to handle conflict: $line"
		;;
	esac
done

git_list_conflicts | while read line; do
	die "Apparently unresolved conflict: $line"
done

git_list_unstaged | while read line; do
	die "Apparently not staged: $line"
done

GIT_AUTHOR_DATE="@0 +0000" GIT_COMMITTER_DATE="@0 +0000" git commit --no-edit
luntrap

if ! final_extraversion="$(makefile_get_extraversion)"; then
	die "Could not determine final extraversion"
fi
final_tag="$tag-$final_extraversion"

if git tag --list | grep -Fx "$final_tag" &>/dev/null; then
	die "Tag $final_tag already exists, not overwriting"
fi
log "Tagging as $final_tag"
git tag "$final_tag"
