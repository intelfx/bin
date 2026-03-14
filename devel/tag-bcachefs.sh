#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=../lib/lib.sh
. lib.sh

BCACHEFS_TOOLS_DIR="$HOME/devel/ext/bcachefs-tools"
BCACHEFS_TOOLS_REMOTE="upstream"
BCACHEFS_KERNEL_DIR="$HOME/devel/ext/linux"
BCACHEFS_KERNEL_REMOTE="bcachefs"

git -C "$BCACHEFS_KERNEL_DIR" fetch "$BCACHEFS_KERNEL_REMOTE"
git -C "$BCACHEFS_TOOLS_DIR" fetch "$BCACHEFS_TOOLS_REMOTE"

set_one_revision() {
	local kind="$1"
	local name="$2"
	local rev="$3"
	shift 3

	case "$kind" in
	tag)    git -C "$BCACHEFS_KERNEL_DIR" tag "$@" "$name" "$rev" ;;
	branch) git -C "$BCACHEFS_KERNEL_DIR" branch -f "$@" "$name" "$rev" ;;
	*) die "set_one_revision: invalid invocation: kind=${kind@Q}" ;;
	esac
}

extract_one_revision() {
	local kind="$1"
	local tools_ref="$2"
	local kernel_ref="$3"

	local rev_file=".bcachefs_revision"

	# try to extract the kernel code revision corresponding to the given tools version
	# 1) from a marker file, if one exists
	# 2) by looking up the most recent commit that updated the kernel code

	if tools_rev="$(git -C "$BCACHEFS_TOOLS_DIR" log -1 --format='%h' "$tools_ref" -- "$rev_file")"; then
		rev="$(git -C "$BCACHEFS_TOOLS_DIR" show "$tools_rev:$rev_file")"
	else
		git -C "$BCACHEFS_TOOLS_DIR" log "$tools_ref" \
			-1 \
			--grep='Update bcachefs sources to ' \
			--format=$'%h\t%S\t%s\n' \
		| IFS=$'\t' read -r tools_rev src subject
		[[ $subject =~ ^Update\ bcachefs\ sources\ to\ ([0-9a-f]+) ]]
		rev="${BASH_REMATCH[1]}"
	fi

	kernel_rev="$(git -C "$BCACHEFS_KERNEL_DIR" rev-parse --verify --short "$rev^{commit}" 2>/dev/null)" || kernel_rev=""
	kernel_rev_existing="$(git -C "$BCACHEFS_KERNEL_DIR" rev-parse --verify --short "$kernel_ref" 2>/dev/null)" || kernel_rev_existing=""

	if [[ ! $kernel_rev ]]; then
		log "tools/$tools_ref ($tools_rev) => kernel/$kernel_ref ($rev) is UNKNOWN"
		return 0
	elif [[ $kernel_rev_existing && $kernel_rev_existing != $kernel_rev ]]; then
		if [[ $kind == tag ]]; then
			log "tools/$tools_ref ($tools_rev) => kernel/$kernel_ref ($kernel_rev) != $kernel_rev_existing, bailing out"
			exit 1
		fi
		log "tools/$tools_ref ($tools_rev) => kernel/$kernel_ref ($kernel_rev) != $kernel_rev_existing, updating"
	elif [[ $kernel_rev_existing == $kernel_rev ]]; then
		log "tools/$tools_ref ($tools_rev) => kernel/$kernel_ref ($kernel_rev) exists"
		return 0
	else
		log "tools/$tools_ref ($tools_rev) => kernel/$kernel_ref ($kernel_rev)"
	fi

	set_one_revision "$kind" "$kernel_ref" "$kernel_rev"
}

git -C "$BCACHEFS_TOOLS_DIR" ls-refs --format '%(refname:short)' 'refs/tags/v*' \
| sort -V \
| while IFS='' read -r tag; do
	extract_one_revision tag "$tag" "bcachefs/${tag#v}"
	last_tools_ref="$tag"
done
extract_one_revision branch "$last_tools_ref" bcachefs-tools/release
extract_one_revision branch "$BCACHEFS_TOOLS_REMOTE/master" bcachefs-tools/master
