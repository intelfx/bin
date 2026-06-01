#!/bin/bash

set -eo pipefail
shopt -s lastpipe
# shellcheck source=../../../bin/lib/lib.sh
. lib.sh

_usage() {
	cat <<EOF
Usage: $0 VERSION
EOF
}


#
# args
#

declare -A _args=(
	['-h|--help']=ARG_USAGE
	['-o|--output-dir:']=ARG_DIR
	[--]=ARGS
)
parse_args _args "$@" || usage
[[ ! $ARG_USAGE ]] || usage
set -- "${ARGS[@]}"

(( $# == 1 )) || usage
TARGET_REF="$1"

[[ $ARG_DIR ]] || ARG_DIR="$PWD"
[[ -d $ARG_DIR ]] || die "Output directory does not exist: ${ARG_DIR@Q}"


#
# main
#

TARGET_REV="$(git rev-parse --verify "$TARGET_REF^{commit}")" \
	|| die "Could not resolve new ref: $TARGET_REF"

log "Exporting patches from: patch/$TARGET_REF/*"

git ls-refs refs/heads/patch/"$TARGET_REF"/ \
	| readarray -t PATCHES

for branch in "${PATCHES[@]}"; do
	# our patch is always a single commit on the tip of this branch
	stem="${branch#"patch/$TARGET_REF/"}"
	[[ $stem != */* ]] || die "Unexpected branch name: $branch"
	file="$ARG_DIR/$stem.diff"
	log "Exporting patch: $stem ($branch) -> $file"

	# mimic original patch format: bare message + patch,
	# omitting the subject line (and the following blank line), then
	# omitting two newlines between the message and the first diff marker
	# (utilize the fact that a commit message always ends with a based-on:),
	# and omitting index lines

	# {
	# 	git log -1 --format=%b -p "$branch" | \
	# 		sed -r \
	# 			-e '/^based-on:/,+2 { /^$/d }' \
	# 			-e '/^diff --git /,+1 { /^index /d };'
	# } >"$file"

	{
		git log -1 --pretty=format:%b "$branch"
		git show --pretty=format: "$branch" \
			| sed -r -e '/^diff --git /,+1 { /^index /d };'
	} >"$file"
done
