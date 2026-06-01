#!/bin/bash

set -eo pipefail
shopt -s lastpipe
# shellcheck source=../../../bin/lib/lib.sh
. lib.sh

_usage() {
	cat <<EOF
Usage: $0 FROM-VERSION TARGET-VERSION
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

(( $# == 2 )) || usage
OLD_REF="$1"
NEW_REF="$2"


#
# functions
#

# helper to update the commit message
git_update_based_on() {
	local target="${1:?}"
	local file="${2:?}"
	sed -r "s|^based-on: .*|based-on: $target|" -i "$file"
}
export -f git_update_based_on


#
# main
#

OLD_REV="$(git rev-parse --verify "$OLD_REF^{commit}")" \
	|| die "Could not resolve old ref: $OLD_REF"
NEW_REV="$(git rev-parse --verify "$NEW_REF^{commit}")" \
	|| die "Could not resolve new ref: $NEW_REF"

log "Rebasing from: $OLD_REF ($OLD_REV)"
log "           to: $NEW_REF ($NEW_REV)"

git ls-refs refs/heads/patch/"$OLD_REF"/ \
	| readarray -t PATCHES_OLD

for branch_old in "${PATCHES_OLD[@]}"; do
	# our patch is always a single commit on the tip of this branch
	stem="${branch_old#"patch/$OLD_REF/"}"
	[[ $stem != */* ]] || die "Unexpected branch name: $branch_old"

	branch_new="patch/$NEW_REF/$stem"
	if git rev-parse --verify --quiet "$branch_new"; then
		log "Skipping patch: $stem (already rebased)"
		continue
	fi
	log "Rebasing patch: $stem ($branch_old -> $branch_new)"

	# extract commit message
	commit_msg="$(git log -1 --format=%B "$branch_old")"
	# strip the subject line (and the next) to get the original patch preamble
	preamble="$(<<<"$commit_msg" tail -n +3)"

	awk <<<"$preamble" -F ': ' '
		/^based-on: / { print $2; exit }
	' | IFS= read -r based_on
	[[ $based_on ]] || die "Could not extract based-on:"

	# rewrite based-on: for patches based on other patches
	# (based-on: patch/master/$other-patch)
	if [[ $based_on =~ ^patch/master/(.+)$ ]]; then
		target="patch/$NEW_REF/${BASH_REMATCH[1]}"
		target_rev="$(git rev-parse --verify "$target")" \
			|| die "Could not resolve rebase target (perhaps the base patch was not rebased yet?): $target"
		# do not rewrite based-on, keep "patch/master/..."
		target_based_on="$based_on"
	elif [[ $based_on == "$OLD_REV" ]]; then
		target="$NEW_REV"
		target_rev="$target"
		# rewrite commit ID in based-on
		target_based_on="$target_rev"
	else
		die "Unexpected based-on: $based_on"
	fi

	Trace git checkout -B "$branch_new" "$branch_old"
	Trace git-rebase-repeatedly --onto "$target" "$branch_new~1" "$branch_new"

	# update commit message if desired
	if [[ $target_based_on != "$based_on" ]]; then
		# we could have passed the new string in an environment variable, which is cleaner,
		# but git only treats $GIT_EDITOR as a shell command if it looks shell-command-like
		# (otherwise it tries to exec directly and complains because an exporter function is not something you can exec)
		GIT_EDITOR="git_update_based_on ${target_based_on@Q}" \
			Trace git commit --amend
	fi

	# XXX
	if { { make conf || make conf || make reconfigure; } && make -j"$(nproc)"; }; then
		log "Test-build OK"
	else
		rc=$?
		err "Test-build FAIL: $rc, exiting"
		exit $rc
	fi
done
