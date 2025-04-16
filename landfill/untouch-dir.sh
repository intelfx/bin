. lib.sh || exit

_usage() {
	cat <<EOF
Usage: $0 [-f|--force]
EOF
}


#
# args
#

declare -A _args=(
	[-h|--help]=ARG_USAGE
	[-f|--force]=ARG_FORCE
	[--]=DIRS
)
parse_args _args "$@" || usage
[[ ! $ARG_USAGE ]] || usage
export ARG_FORCE


#
# functions
#

untouch_one_dir() {
	set -eo pipefail
	shopt -s lastpipe

	local dir="$1"
	[[ -d "$dir" ]] || { err "$dir: not a directory, skipping"; return 1; }

	find "$dir" -mindepth 1 -maxdepth 1 -printf '%T@\n' \
	| sort -n \
	| tail -n1 \
	| { IFS='' read -r mtime ||:; } \
		|| return 1

	if ! [[ $mtime ]]; then
		if (( ARG_FORCE )); then
			log "$dir: no files, resetting to epoch"
			mtime=0
		else
			log "$dir: no files, skipping"
			return 0
		fi
	fi
	touch -d "@$mtime" "$dir" || return 1
}
libsh_export_log
export -f untouch_one_dir


#
# main
#

rc=0
for dir in "${DIRS[@]}"; do
	if ! [[ -d "$dir" ]]; then
		rc=1
		err "$dir: not a directory, skipping"
		continue
	fi
	if ! find "$dir" -depth -type d | parallel -j1 'untouch_one_dir'; then
		rc=$?
		err "$dir: failed to process"
	fi
done
exit $rc
