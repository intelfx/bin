#!/bin/bash

set -eo pipefail
shopt -s lastpipe

. lib.sh || exit

log "Fetching remotes"
git fetch -j$(nproc) --multiple stable arch pf

git_list_versions() {
	# TODO: "rolling back" changes with sed is ugly
	# separate the tag and the sorting key
	git tag --list \
		| grep -Ex 'v[0-9]+\.[0-9]+(\.[0-9]+)?' \
		| sort -V "$@"
}

git_list_versions_rc() {
	# TODO: "rolling back" changes with sed is ugly
	# separate the tag and the sorting key
	git tag --list \
		| grep -Ex 'v[0-9]+\.[0-9]+(.[0-9]+)?(-rc[0-9]+)?' \
		| sed -r 's|-rc|~rc|' \
		| sort -V "$@" \
		| sed -r 's|~rc|-rc|'
}

git_verify() {
	git rev-parse --verify --quiet "$1" >/dev/null
}

log "Determining versions"
tag="$(git_list_versions | tail -n1)"
git_verify "$tag" || die "Failed to determine latest stable, exiting"
log " Latest stable: $tag"

arch_tag="$(git tag --list "$tag-arch*" | grep -E -- '-arch[0-9]+$' | sort -V)"
git_verify "$arch_tag" || die "Failed to determine latest -arch, exiting"
log " Latest -arch tag: $arch_tag"

release="$(<<<"$tag" sed -nr 's|^v([0-9]+\.[0-9]+)(\.[0-9]+)?$|\1|p')"
git_verify "v$release" || die "Failed to determine major release, exiting"
log " Major release: $release"

eval "$(globaltraps)"

log "Merging -pf"
git checkout -f "$arch_tag"
if ! git merge --no-commit --no-rerere "pf/pf-$release"; then
	ltrap 'git merge --abort'
fi

git_list_conflicts() {
	git status --untracked=no --porcelain | { grep -E '^(AA|DD|.U|U.) ' || true; }
}

git_list_unstaged() {
	git status --untracked=no --porcelain | { grep -E '^.[^ ] ' || true; }
}

git_list_parse() {
	local line="$1"
	index="${line:0:1}"
	worktree="${line:1:1}"
	file="${line:3}"
}

makefile_get_extraversion() {
	<Makefile sed -nr 's|^EXTRAVERSION = -([^ ]+)$|\1|p' | head -n1 | grep .
}

merge_makefile() {
	local pf_extraversion ours_extraversion

	git checkout --theirs Makefile
	if ! pf_extraversion="$(makefile_get_extraversion)"; then
		die "Could not parse -pf EXTRAVERSION"
	fi

	git checkout --ours Makefile
	if ! ours_extraversion="$(makefile_get_extraversion)"; then
		die "Could not parse main EXTRAVERSION"
	fi

	sed -r "s|^(EXTRAVERSION = ).*$|\1-$ours_extraversion$pf_extraversion|" -i Makefile
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

if git_verify "$final_tag"; then
	die "Tag $final_tag already exists, not overwriting"
fi
log "Tagging as $final_tag"
git tag "$final_tag"
