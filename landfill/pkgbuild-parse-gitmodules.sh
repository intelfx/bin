#!/bin/bash

set -eo pipefail
shopt -s lastpipe

. lib.sh || exit


#
# args
#

_usage() {
	cat <<EOF
Usage: ${0##*/}
EOF
}

declare -A _args=(
	[--internal-subpath:]="ARG_SUBPATH"
	[--help|-h]="ARG_HELP"
)
parse_args _args "$@" || usage


#
# main
#

git_args=()

if [[ ${ARG_SUBPATH+set} ]]; then
	git_args+=( -C "$ARG_SUBPATH" )
fi

declare -A submodules
declare -A sub_to_url
declare -A sub_to_path

git "${git_args[@]}" config --file .gitmodules --list | while IFS='=' read -r key value; do
	case "$key" in
	submodule.*.path)
		sub="$key"; sub="${sub%.path}"; sub="${sub#submodule.}"
		submodules["$sub"]=1
		sub_to_path["$sub"]="$value"
		;;
	submodule.*.url)
		sub="$key"; sub="${sub%.url}"; sub="${sub#submodule.}"
		submodules["$sub"]=1
		sub_to_url["$sub"]="$value"
		;;
	esac
done

if ! [[ ${ARG_SUBPATH+set} ]]; then
	printf "%s\n" "declare -g -A _gitmodules=("
fi

for sub in "${!submodules[@]}"; do
	url="${sub_to_url["$sub"]:?}"
	subspec="${ARG_SUBPATH+"${ARG_SUBPATH@Q}:"}${sub@Q}"

	printf "\t[%s]=%s\n" "$subspec" "${url@Q}"
done

for sub in "${!submodules[@]}"; do
	path="${sub_to_path["$sub"]:?}"
	subpath="${ARG_SUBPATH+"$ARG_SUBPATH/"}$path"

	if [[ -e "$subpath/.gitmodules" ]]; then
		"$0" --internal-subpath "$subpath"
	fi
done

if ! [[ ${ARG_SUBPATH+set} ]]; then
	printf "%s\n" ")"
fi
