#!/bin/bash

set -eo pipefail
shopt -s lastpipe

. lib.sh || exit

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

declare -A PARSE_ARGS=(
	[-c]="ARG_CONFLICTS"
	[--conflicts]="ARG_CONFLICTS"
	[-b:]="ARG_MAJOR"
	[--branch:]="ARG_MAJOR"
	[--major:]="ARG_MAJOR"
	[-v:]="ARG_MINOR"
	[--version:]="ARG_MINOR"
	[--minor:]="ARG_MINOR"
	[--pf:]="ARG_PF"
)
parse_args PARSE_ARGS "$@"

log "Fetching remotes"
git fetch -j$(nproc) --multiple stable arch pf

log "Determining versions"
if [[ "$ARG_MINOR" ]]; then
	tag="$(git_list_versions | grep -Fx "$ARG_MINOR" | tail -n1)"
	git_verify "$tag" || die "Failed to find $ARG_MINOR, exiting" || true
	log " Requested version: $tag"
elif [[ "$ARG_MAJOR" ]]; then
	tag="$(git_list_versions | grep -Ex "$ARG_MAJOR(\.[0-9]+)?" | tail -n1)"
	git_verify "$tag" || die "Failed to determine latest patch for $ARG_MAJOR, exiting" || true
	log " Latest patch for $ARG_MAJOR: $tag"
else
	tag="$(git_list_versions | tail -n1)"
	git_verify "$tag" || die "Failed to determine latest stable, exiting" || true
	log " Latest stable: $tag"
fi

release="$(<<<"$tag" sed -nr 's|^v([0-9]+\.[0-9]+)(\.[0-9]+)?$|\1|p')" || true
git_verify "v$release" || die "Failed to determine major release, exiting"
log " Major release: $release"

if [[ "$ARG_PF" ]]; then
	pf_tag="$ARG_PF"
	git_verify "$pf_tag" || die "Failed to find $pf_tag, exiting" || true
	log " Requested -pf tag: $pf_tag"
else
	pf_tag="$(git tag --list "v$release-pf*" | grep -E -- '-pf[0-9]+$' | sort -V | tail -n1)" || true
	git_verify "$pf_tag" || die "Failed to determine latest -pf, exiting"
	log " Latest -pf tag: $pf_tag"
fi

arch_tag="$(git tag --list "$tag-arch*" | grep -E -- '-arch[0-9]+$' | sort -V | tail -n1)" || true
git_verify "$arch_tag" || die "Failed to determine latest -arch, exiting"
log " Latest -arch tag: $arch_tag"

eval "$(globaltraps)"

log "Merging -pf"
git checkout -f "$arch_tag"
if ! git merge --no-commit "$pf_tag"; then
	ltrap 'git merge --abort'
fi

log "Handling conflicts"
conflicts=0
git_list_conflicts | while read line; do
	git_list_parse "$line"
	case "$file" in
	Makefile)
		merge_makefile
		;;
	*)
		err "Conflict: $line"
		(( ++conflicts ))
		;;
	esac
done
if (( conflicts )); then
	if (( ARG_CONFLICTS )); then
		err "Found conflicts, launching interactive shell"
		err "To continue, resolve and stage conflicts and exit 0"
		err "To abort, exit 1"
		"$SHELL" -i
	else
		die "Found conflicts, exiting"
	fi
fi

git_list_conflicts | while read line; do
	die "Apparently unresolved conflict: $line"
done

git_list_unstaged | while read line; do
	die "Apparently not staged: $line"
done

log "Committing result"
GIT_AUTHOR_DATE="@0 +0000" GIT_COMMITTER_DATE="@0 +0000" git commit --no-edit
luntrap

if ! final_extraversion="$(makefile_get_extraversion)"; then
	die "Could not determine final extraversion"
fi
final_tag="$tag-$final_extraversion"

if git_verify "$final_tag"; then
	if [[ "$(git rev-parse HEAD)" == "$(git rev-parse "$final_tag")" ]]; then
		err "Tag $final_tag already exists, ignoring"
		exit 0
	fi
	die "Tag $final_tag already exists, not overwriting"
fi
log "Tagging as $final_tag"
git tag "$final_tag"
