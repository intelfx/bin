#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=../lib/lib.sh
. lib.sh

BCACHEFS_TOOLS_DIR="$HOME/devel/tmp/bcachefs-tools"
BCACHEFS_TOOLS_REMOTE="upstream"
BCACHEFS_KERNEL_DIR="$HOME/devel/tmp/linux-bcachefs"
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

	local force_update=0
	local arg
	for arg in "${@:4}"; do
		case "$arg" in
		--force-update) force_update=1 ;;
		*) die "extract_one_revision: invalid arguments: ${*@Q}" ;;
		esac
	done

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

	# if the commit does not exist, try to fetch it directly and retry resolving
	if [[ ! $kernel_rev ]] && (( force_update )); then
		git -C "$BCACHEFS_KERNEL_DIR" fetch "$BCACHEFS_KERNEL_REMOTE" "$rev" ||:
		kernel_rev="$(git -C "$BCACHEFS_KERNEL_DIR" rev-parse --verify --short "$rev^{commit}" 2>/dev/null)" || kernel_rev=""
	fi

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

sync_one_revision() {
	local kind="$1"
	local tools_ref="$2"
	local kernel_ref="$3"

	local force_update=0
	local arg
	for arg in "${@:4}"; do
		case "$arg" in
		--force-update) force_update=1 ;;
		*) die "extract_one_revision: invalid arguments: ${*@Q}" ;;
		esac
	done

	tools_rev="$(git -C "$BCACHEFS_TOOLS_DIR" rev-parse --short "$tools_ref^{commit}")"
	kernel_rev_existing="$(git -C "$BCACHEFS_KERNEL_DIR" rev-parse --verify --short "$kernel_ref^{commit}" 2>/dev/null)" || kernel_rev_existing=""

	# superficial check -- if a tag exists, do not bother replaying source changes, assume it's good
	if [[ $kernel_rev_existing && $kind == tag ]]; then
		log "tools/$tools_ref ($tools_rev) => kernel/$kernel_ref ($kernel_rev_existing) exists"
		return 0
	fi

	git -C "$BCACHEFS_TOOLS_DIR" checkout -f "$tools_ref"
	git -C "$BCACHEFS_KERNEL_DIR" checkout -f "${parent_kernel_ref:?}"
	rsync \
		-r -lDH --chmod=ugo=rwX --delete-after \
		--exclude 'util/mean_and_variance_test.c' \
		"$BCACHEFS_TOOLS_DIR/fs/" "$BCACHEFS_KERNEL_DIR/fs/bcachefs/"

	git update-index --refresh -q &>/dev/null ||:
	git -C "$BCACHEFS_KERNEL_DIR" add -A fs/bcachefs/

	if git -C "$BCACHEFS_KERNEL_DIR" diff-index --quiet --cached HEAD --; then
		log "tools/$tools_ref ($tools_rev) => no change"
		return 0
	fi

	# read author identity and timestamp of the release commit
	git -C "$BCACHEFS_TOOLS_DIR" log "$tools_rev" \
		-1 \
		--format=$'%an\t%ae\t%ad\n' \
	| IFS=$'\t' read -r c_name c_email c_date

	# read commit hash and subject of the last relevant commit
	git -C "$BCACHEFS_TOOLS_DIR" log "$tools_rev" \
		-1 \
		--format=$'%h\t%s\n' \
		-- fs/ \
	| IFS=$'\t' read -r cc_hash cc_subject

	# reset both author and committer details to make the commit ID deterministic
	# GIT_AUTHOR_NAME="$c_name" GIT_AUTHOR_EMAIL="$c_email" \
	# GIT_COMMITTER_NAME="$c_name" GIT_COMMITTER_EMAIL="$c_email" \
	GIT_AUTHOR_DATE="$c_date" \
	GIT_COMMITTER_DATE="$c_date" \
	git -C "$BCACHEFS_KERNEL_DIR" commit -m "Update bcachefs sources to $cc_hash $cc_subject"

	kernel_rev="$(git -C "$BCACHEFS_KERNEL_DIR" rev-parse --short HEAD)"

	if [[ $kernel_rev_existing && $kernel_rev_existing != $kernel_rev ]]; then
		if [[ $kind == tag ]]; then
			log "tools/$tools_ref ($tools_rev) => kernel/$kernel_ref ($kernel_rev) != $kernel_rev_existing, bailing out"
			exit 1
		fi
		log "tools/$tools_ref ($tools_rev) => kernel/$kernel_ref ($kernel_rev) != $kernel_rev_existing, updating"
	elif [[ $kernel_rev_existing == $kernel_rev ]]; then
		log "tools/$tools_ref ($tools_rev) => kernel/$kernel_ref ($kernel_rev_existing) exists"
		return 0
	else
		log "tools/$tools_ref ($tools_rev) => kernel/$kernel_ref ($kernel_rev)"
	fi
	set_one_revision "$kind" "$kernel_ref" "$kernel_rev"
}

# $1 is greater than $2
vergreater() {
	local ret
	ret="$(vercmp "${1##v}" "${2##v}")"
	(( ret > 0 ))
}

git -C "$BCACHEFS_TOOLS_DIR" ls-refs --format '%(refname:short)' 'refs/tags/v*' \
| sort -V \
| while IFS='' read -r tag; do
	if vergreater "$tag" "v1.38.3"; then
		break
	fi
	extract_one_revision tag "$tag" "bcachefs/${tag#v}"
	last_tools_ref="$tag"
	last_kernel_ref="bcachefs/${tag#v}"
done
# extract_one_revision branch "$last_tools_ref" bcachefs-tools/release --force-update
# extract_one_revision branch "$BCACHEFS_TOOLS_REMOTE/master" bcachefs-tools/master --force-update

git -C "$BCACHEFS_TOOLS_DIR" ls-refs --format '%(refname:short)' 'refs/tags/v*' \
| sort -V \
| while IFS='' read -r tag; do
	if ! vergreater "$tag" "v1.38.3"; then
		continue
	fi

	# this is used as the parent of the generated commit
	# set it here so that on the last iteration, both the last release tag
	# and the release branch will all use the same parent (previous release)
	parent_kernel_ref="$last_kernel_ref"
	sync_one_revision tag "$tag" "bcachefs/${tag#v}"
	last_tools_ref="$tag"
	last_kernel_ref="bcachefs/${tag#v}"
done
sync_one_revision branch "$last_tools_ref" bcachefs-tools/release

# master is on top of the last release, so advance the parent here
parent_kernel_ref="$last_kernel_ref"
sync_one_revision branch "$BCACHEFS_TOOLS_REMOTE/master" bcachefs-tools/master
