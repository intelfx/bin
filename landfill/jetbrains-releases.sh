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

RELEASE_TYPES=()
ARG_JSON=0
while (( $# )); do
	case "$1" in
	--json)
		ARG_JSON=1
		;;
	-*)
		usage "unknown option: ${1@Q}"
		;;
	*)
		RELEASE_TYPES+=("$1")
		;;
	esac
	shift
done

if [[ ${RELEASE_TYPES+set} ]]; then
	RELEASE_TYPES_RE="$(IFS='|'; echo "${RELEASE_TYPES[*]}")"
else
	RELEASE_TYPES_RE=".*"
fi

PRODUCTS_LIST=(RR PCC PCP CL DG WS GO)
LAST_N=5

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
