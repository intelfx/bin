#!/bin/bash

set -eo pipefail
shopt -s lastpipe
# shellcheck source=../../../bin/lib/lib.sh
. lib.sh

_usage() {
	cat <<EOF
Usage: $0 TARGET-VERSION
EOF
}


#
# args
#

declare -A _args=(
	['-h|--help']=ARG_USAGE
	[--]=ARGS
)
parse_args _args "$@" || usage
[[ ! $ARG_USAGE ]] || usage
set -- "${ARGS[@]}"

(( $# == 1 )) || usage
TARGET_REF="$1"


#
# main
#

TARGET_REV="$(git rev-parse --verify "$TARGET_REF")" \
	|| die "Could not resolve target ref: $TARGET_REF"

process_one() {
	local patch="$1"
	local name="${patch##*/}"
	local stem="${name%.diff}"
	local LIBSH_LOG_PREFIX="$name"

	# based_on="$(sed <"$patch" -nr '/^based-on: / { s|^based-on: (.+)$|\1|; s|/master/|/'"$TARGET_REF"'/|; p }')"
	# [[ $based_on ]] || die "Could not extract based-on:"

	awk <"$patch" '
		BEGIN { preamble = "" }
		{ preamble = preamble "\n" $0 }
		/^based-on: / { print preamble; exit }
	' | { IFS= read -r -d '' preamble ||:; }

	awk <<<"$preamble" -F ': ' '
		/^based-on: / { print $2; exit }
	' | IFS= read -r based_on
	[[ $based_on ]] || die "Could not extract based-on:"

	# rewrite based-on: for patches based on other patches
	# (based-on: patch/master/$other-patch)
	if [[ $based_on =~ ^patch/master/(.+)$ ]]; then
		based_on="patch/$TARGET_REF/${BASH_REMATCH[1]}"
	fi

	based_rev="$(git rev-parse --verify "$based_on")" \
		|| die "Could not resolve based-on: $based_on"

	# verify that we are applying the patch to the correct upstream version
	# (do it by finding the closest tag; this also accommodates patches based on other patches)
	local based_tag target_tag
	based_tag="$(git describe --tags --abbrev=0 "$based_on")"
	target_tag="$(git describe --tags --abbrev=0 "$TARGET_REF")"
	[[ "$based_tag" == "$target_tag" ]] || die "Specified version does not match based-on: $TARGET_REF != $based_on"


	Trace git checkout -b "patch/$TARGET_REF/$stem" "$based_on"
	Trace git apply -3 "$patch"
	Trace git commit -m "Patch: $name"$'\n\n'"$preamble"
}


for patch in ../rsync-patches/*.diff; do
	process_one "$patch"
done
