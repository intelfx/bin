#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=../lib/lib.sh
. lib.sh

_usage() {
	cat <<EOF
Usage: $0 [--json] [RELEASE-TYPES...]

Options:
  --json	Output raw JSON instead of a table
EOF
	exit 1
}

declare -A _args=(
	['--json']="ARG_JSON"
	['-r|--release:']="ARG_RELEASES split=' ' append"
	['-p|--product:']="ARG_PRODUCTS split=' ' append"
	['-n|--last:']="ARG_LAST"
	[--]="ARGS"
)
parse_args _args "$@" || usage

# compat
ARG_RELEASES+=("${ARGS[@]}")

if [[ ${ARG_RELEASES+set} ]]; then
	RELEASE_TYPES_RE="$(join '|' "${ARG_RELEASES[@]}")"
else
	RELEASE_TYPES_RE=".*"
fi

if [[ ${ARG_PRODUCTS+set} ]]; then
	PRODUCTS_LIST=()
	for p in "${ARG_PRODUCTS[@]}"; do
		case "${p,,}" in
		rustrover) PRODUCTS_LIST+=("RR") ;;
		pycharm) PRODUCTS_LIST+=("PCC" "PCP") ;;
		clion) PRODUCTS_LIST+=("CL") ;;
		datagrip) PRODUCTS_LIST+=("DG") ;;
		webstorm) PRODUCTS_LIST+=("WS") ;;
		goland) PRODUCTS_LIST+=("GO") ;;
		*)
			if [[ "$p" =~ ^[a-zA-Z]{2,3}$ ]]; then
				PRODUCTS_LIST+=("${p^^}")
			else
				die "Invalid product code: ${p@Q}"
			fi
		;;
		esac
	done
else
	PRODUCTS_LIST=(RR PCC PCP CL DG WS GO)
fi

if [[ ${ARG_LAST+set} ]]; then
	LAST_N="$ARG_LAST"
else
	LAST_N=5
fi

# shellcheck disable=SC2016
JQ_PROG_FIRST='
| map({ code, name, releases })
| map(select(.code | IN($products | split(" ") | .[])))
| map(.releases |= (.
	| map(select(.build))
	| map(select(.type | match($release_types)))
))
| map(select(.releases | length > 0))
| map(.releases |= (.
	| sort_by(.build | split(".") | map(tonumber))
	| reverse
	| .[0:$last_n]
))
'

# shellcheck disable=SC2016
JQ_PROG_TABLE='
| ($fields_list | split(" ")) as $fields
| map(. as $o | .releases | map(. as $r
	| ($o + $r) as $combined
	| $fields | map($combined[.])
	| join("\t")
))
| flatten
'

# shellcheck disable=SC2016
JQ_PROG_RAW='
| map(.releases |= (.
	| map(.
		| del(.whatsnew, .uninstallFeedbackLinks, .licenseRequired)
		| .patches |= ({ unix })
		| .downloads |= ({ linux, linuxARM64 })
	)
))
'

do_fetch_process() {
	local jq_prog="${@: -1}"
	local -a jq_args=("${@:1:$#-1}")

	curl -fsS 'https://data.services.jetbrains.com/products' \
		| jq \
			--arg products "${PRODUCTS_LIST[*]}" \
			--arg release_types "$RELEASE_TYPES_RE" \
			--argjson last_n "$LAST_N" \
			"${jq_args[@]}" \
			". $JQ_PROG_FIRST $jq_prog"
}

if (( ARG_JSON )); then
	do_fetch_process \
		"$JQ_PROG_RAW"
	exit
fi

FIELDS=(code name type date version build)
COLUMNS=(CODE NAME TYPE DATE VERSION BUILD)
{
	(IFS=$'\t'; echo "${COLUMNS[*]}")
	do_fetch_process \
		--arg fields_list "${FIELDS[*]}" \
		-r \
		"$JQ_PROG_TABLE []"
} | column -Lt -s $'\t'
