#!/bin/bash

. lib.sh || exit

_usage() {
	cat <<EOF
Usage: $0 [PKGBUILD] [REPO-ROOT-DIR]
EOF
}


#
# args
#

declare -A _args=(
	[-h|--help]=ARG_USAGE
	[--]=ARGS
)
parse_args _args "$@" || usage
[[ ! $ARG_USAGE ]] || usage

case "${#ARGS[@]}" in
0|1|2) ;;
*) usage "expected at most 2 positional arguments" ;;
esac


#
# main
#

unset pkgbuild
unset repo_root

for arg in "${ARGS[@]}"; do
	if [[ -f $arg ]] && ! [[ ${pkgbuild+set} ]]; then
		pkgbuild="$arg"
	elif [[ -d $arg && -f $arg/PKGBUILD ]] && ! [[ ${pkgbuild+set} ]]; then
		pkgbuild="$arg/PKGBUILD"
	elif [[ -d $arg ]] && ! [[ ${repo_root+set} ]]; then
		repo_root="$arg"
	fi
done

if ! [[ ${pkgbuild+set} ]]; then
	if [[ -f PKGBUILD ]]; then
		pkgbuild=PKGBUILD
	else
		usage "expected a PKGBUILD argument"
	fi
fi

if ! [[ ${repo_root+set} ]]; then
	if ! aur repo --status | awk -F: '$1 == "root" { print $2 }' | IFS= read -r repo_root; then
		usage "expected a REPO-ROOT-DIR argument"
	fi
fi

rc=0

log "Running namcap on ${pkgbuild@Q}"
namcap "$pkgbuild" || rc=$?

pkgs=()
(cd "$(dirname "$pkgbuild")" && aur build--pkglist) | while read f; do
	pkgs+=( "$repo_root/$(basename "$f")" )
done

for f in "${pkgs[@]}"; do
	if [[ -e $f ]]; then
		log "Running namcap on ${f@Q}"
		namcap "$f" || rc=$?
	else
		err "Could not find ${f@Q} -- package not built?"
		rc=1
	fi
done

exit $rc

