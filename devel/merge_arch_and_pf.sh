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
		| grep -Ex 'v[0-9]+\.[0-9]+(-rc[0-9]+|\.[0-9]+)?' \
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

git_maybe_tag() {
	local tag="$1"

	if ! git_verify "$tag"; then
		log "Tagging as $tag"
		git tag "$tag"
	elif [[ "$(git rev-parse HEAD)" == "$(git rev-parse "$tag")" ]]; then
		log "Tag $tag already exists, ignoring"
	else
		die "Tag $tag already exists, not overwriting"
	fi
}

makefile_get_field() {
	local field="$1" strip_prefix="${2-""}"
	sed -nr "s|^${field} *= *${strip_prefix}([^ ]+)$|\1|p" Makefile | head -n1 | grep .
}

makefile_set_field() {
	local field="$1" value="$2"
	sed -r "s|^(${field} *= *).*$|\1${value}|" -i Makefile
}

merge_makefile_pf() {
	local pf_extraversion ours_extraversion

	git checkout --theirs Makefile
	if ! pf_extraversion="$(makefile_get_field EXTRAVERSION "-")"; then
		die "Could not parse -pf EXTRAVERSION"
	fi

	git checkout --ours Makefile
	if ! ours_extraversion="$(makefile_get_field EXTRAVERSION "-")"; then
		die "Could not parse ours EXTRAVERSION"
	fi

	makefile_set_field EXTRAVERSION "-$ours_extraversion$pf_extraversion"
	git add Makefile
}


merge_pf() {
	local pf_tag="$1"

	eval "$(ltraps)"

	log "Merging -pf"
	git merge --no-ff --no-commit "$pf_tag" || true
	ltrap 'git merge --abort'

	log "Handling conflicts"
	git_list_conflicts | while IFS='' read -r line; do
		git_list_parse "$line"
		case "$file" in
		Makefile)
			merge_makefile_pf
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

	git_list_conflicts | while IFS='' read -r line; do
		die "Apparently unresolved conflict: $line"
	done

	git_list_unstaged | while IFS='' read -r line; do
		die "Apparently not staged: $line"
	done

	log "Committing result"
	git commit --no-edit
	luntrap
}
declare -A PARSE_ARGS=(
	[--rc]="ARG_RC"
	[-c]="ARG_CONFLICTS"
	[--conflicts]="ARG_CONFLICTS"
	[-b:]="ARG_MAJOR"
	[--branch:]="ARG_MAJOR"
	[--major:]="ARG_MAJOR"
	[-v:]="ARG_MINOR"
	[--version:]="ARG_MINOR"
	[--minor:]="ARG_MINOR"
	[--pf:]="ARG_PF"
	[-k]="ARG_KEEP"
	[--keep]="ARG_KEEP"
)
parse_args PARSE_ARGS "$@"


#
# main
#

log "Fetching remotes"
git fetch -j$(nproc) --multiple stable arch pf

# Make everything stable and reproducible
export \
	GIT_AUTHOR_DATE="@0 +0000" \
	GIT_COMMITTER_DATE="@0 +0000" \
	# EOL

#
# Determine patchset tips to use
#

if [[ $ARG_RC ]]; then
	git_list_versions() { git_list_versions_rc "$@"; }
fi

log "Determining versions"
if [[ "$ARG_MINOR" ]]; then
	if tag="$(git_list_versions | grep -Fx "$ARG_MINOR" | tail -n1)" \
	&& git_verify "$tag"; then
		log " Requested release: $tag"
	else
		die "Failed to verify requested release: $ARG_MINOR"
	fi
elif [[ "$ARG_MAJOR" ]]; then
	if tag="$(git_list_versions | grep -Ex "$ARG_MAJOR(\.[0-9]+)?" | tail -n1)" \
	&& git_verify "$tag"; then
		log " Latest release for requested branch: $tag"
	elif tag="$(git_list_versions | grep -Ex "$ARG_MAJOR-rc[0-9]+" | tail -n1)" \
	&& git_verify "$tag"; then
		log " Latest -rc for requested branch: $tag"
	else
		die "Failed to determine latest release for requested branch: $ARG_MAJOR"
	fi
else
	if tag="$(git_list_versions | tail -n1)" \
	&& git_verify "$tag"; then
		log " Latest release: $tag"
	else
		die "Failed to determine latest release"
	fi
fi

if major="$(<<<"$tag" sed -nr 's#^v([0-9]+\.[0-9]+)(\.[0-9]+)?$#\1#p')" \
&& git_verify "v$major"; then
	log " Major branch: $major"
elif major="$(<<<"$tag" sed -nr 's#^v([0-9]+\.[0-9]+)(-rc[0-9]+)?$#\1#p')"; then
	log " Major branch: $major (${tag#v$major})"
else
       die "Failed to determine major branch, exiting"
fi

if [[ "$ARG_PF" ]] \
&& pf_tag="$ARG_PF" \
&& git_verify "$pf_tag"; then
	log " Requested -pf tag: $pf_tag"
elif pf_tag="$(git tag --list "v$major-pf*" | grep -E -- '-pf[0-9.]+$' | sort -V | tail -n1)" \
  && git_verify "$pf_tag"; then
	log " Latest -pf tag: $pf_tag"
elif pf_tag="pf/pf-$major" \
  && git_verify "$pf_tag"; then
	log " Using -pf branch: $pf_tag"
else
	die "Failed to determine latest -pf, exiting"
fi

if arch_tag="$(git tag --list "${tag}*arch*" | grep -E -- "-?arch[0-9]+$" | sort -V | tail -n1)" \
&& git_verify "$arch_tag"; then
	log " Latest -arch tag: $arch_tag"
else
	die "Failed to determine latest -arch for $tag, exiting"
fi

#
# Compute git version string
#

tag_base="$tag"
tag_extras=()
if [[ $tag != *-* ]]; then
	:
elif [[ $tag =~ ^(.+)-(rc[0-9]+)$ ]]; then
	tag_base="${BASH_REMATCH[1]}"
	tag_extras+=( "${BASH_REMATCH[2]}" )
else
	die "Failed to extract base version ($tag)"
fi

if [[ $arch_tag =~ (arch[0-9]+)$ ]]; then
	arch_version="${BASH_REMATCH[1]}"
else
	die "Failed to extract -arch version ($arch_tag)"
fi
tag_extras+=( "$arch_version" )

pf_desc="$(git describe --tags "$pf_tag")"
if [[ $pf_desc =~ (pf[0-9.]+)$ ]]; then
	pf_version="${BASH_REMATCH[1]}"
elif [[ $pf_desc =~ (pf[0-9.]+)-([0-9]+)-g.+$ ]]; then
	pf_version="${BASH_REMATCH[1]}+${BASH_REMATCH[2]}"
elif [[ $pf_desc =~ -([0-9.]+)-g.+$ ]]; then
	# unreleased, i. e. `--pf pf/pf-6.7`
	pf_version="pf0+${BASH_REMATCH[1]}"
else
	die "Failed to extract -pf version ($pf_tag) ($pf_desc)"
fi
tag_extras+=( "$pf_version" )

IFS=''; final_tag="$tag_base-${tag_extras[*]}"; unset IFS
log " Final tag: $final_tag"

if [[ "$ARG_KEEP" ]] && git_verify "$final_tag"; then
	log "Tag $final_tag already exists and -k/--keep specified, not overwriting"
	exit 0
fi

eval "$(globaltraps)"

#
# Actually merge patchset tips
#

log "Checking out base tag"
git checkout -f "$tag"

log "Merging -arch"
if ! git merge --ff "$arch_tag"; then
	die "Failed to merge -arch -- not fast-forward?"
fi

merge_pf "$pf_tag"
git_maybe_tag "$final_tag"
