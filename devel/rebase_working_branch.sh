#!/bin/bash

set -eo pipefail
shopt -s lastpipe

. lib.sh || exit


#
# functions
#

git_verify() {
	git rev-parse --verify --quiet "$1" >/dev/null
}

git_find_base_version() {
	git describe \
		--tags \
		--abbrev=0 \
		--match 'v*' \
		--match 'v*.*' \
		--exclude 'v*.*-*' \
		"$@"
		#--exclude 'v*.*.*' \
}

function git_find_master() {
	local name ref
	for name in master main; do
		for ref in "$name@{u}" "$name"; do
			if git_verify "$ref"; then
				log "Using ${ref@Q} as the master ref"
				printf "%s\t%s\n" "$name" "$ref"
				return 0
			fi
		done
	done
	return 1
}

_usage() {
	cat <<EOF
Usage: $0 [-f|--find-tag] <onto> <branch>...
Options:
	-f, --find-tag		If a branch name does not end with a version,
				use \`git describe\` to find the closest tag
				(if not specified, master is used as the branch
				upstream)
EOF
}


#
# args
#

declare -A _args=(
	[-h|--help]=ARG_USAGE
	[-f|--find-tag]=ARG_FIND_TAG
	[--]=ARGS
)

parse_args _args "$@" || usage
(( ! ARG_USAGE )) || usage

if (( ${#ARGS[@]} > 1 )); then
	TARGET="${ARGS[0]}"
	BRANCHES=( "${ARGS[@]:1}" )
elif (( ${#ARGS[@]} == 1 )); then
	TARGET="${ARGS[0]}"
	if ! head="$(git symbolic-ref --short HEAD)"; then
		die "No branches to rebase, and HEAD is not on a branch"
	fi
	BRANCHES=( "$head" )
else
	usage "Expected 1 or more arguments"
fi


#
# main
#

if ! git_verify "$TARGET"; then
	die "Invalid base: ${TARGET@Q}"
fi

if ! [[ $TARGET =~ ([0-9.]+)$ ]]; then
	die "Invalid base: ${TARGET@Q}"
fi

TARGET_VERSION="${BASH_REMATCH[1]}"
PREFIX="${TARGET%"$TARGET_VERSION"}"

log "Target ref: $TARGET"
log "Target version: $TARGET_VERSION"
if [[ $PREFIX ]]; then
	log "Ref prefix: $PREFIX"
fi

function process_branch() {
	local branch="$1"
	local LIBSH_LOG_PREFIX="[$branch]"

	log "Rebasing"

	if ! git_verify "$branch"; then
		err "Invalid working branch"
		return 1
	fi

	local branch_name branch_version
	if [[ $branch =~ (.+)-([0-9.]+)$ ]] \
	&& base="$PREFIX${BASH_REMATCH[2]}" \
	&& git_verify "$base"
	then
		suffix="-${BASH_REMATCH[2]}"
		log "Using branch name suffix ${suffix@Q}"
		branch_version="${BASH_REMATCH[2]}"
		branch_name="${BASH_REMATCH[1]}"
	elif (( ARG_FIND_TAG )) \
	  && base="$(git_find_base_version "$branch")" \
	  && git_verify "$base"
	then
		log "Using dynamically determined branch base ${base@Q}"
		branch_version="${base#"$PREFIX"}"
		branch_name="${branch%"-$branch_version"}"
	elif (( ! ARG_FIND_TAG )) \
	  && git_find_master | IFS=$'\t' read -r branch_version base
	then
		log "Could not determine working branch base, using master as base"
		branch_name="$branch"
	else
		err "Unable to determine working branch base, and unable to find master ref"
		return 1
	fi

	local new_branch="$branch_name-$TARGET_VERSION"

	log "Old branch: $branch (@ $base)"
	log "New branch: $new_branch (@ $TARGET)"

	local old_ref new_ref
	old_ref="$(git rev-parse --verify --quiet "$branch")"
	if new_ref="$(git rev-parse --verify --quiet "$new_branch")" \
	&& [[ $new_ref != "$old_ref" ]]; then
		err "New branch ($new_branch) exists, aborting"
		return 1
	fi

	trace git checkout --detach "$TARGET" || return
	trace git branch -f "$new_branch" "$branch" || return
	trace git rebase-repeatedly --onto "$TARGET" "$base" "$new_branch" || return
}

rc=0
for b in "${BRANCHES[@]}"; do
	process_branch "$b" || rc=1
done

exit $rc
