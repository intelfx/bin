#!/bin/bash

set -eo pipefail
shopt -s lastpipe

if (( $# )); then
	RELEASE_TYPES_RE="$(IFS='|'; echo "$*")"
else
	RELEASE_TYPES_RE=".*"
fi

PRODUCTS_LIST=(RR PCC PCP CL DG WS GO)
LAST_N=5

# shellcheck disable=SC2016
JQ_PROG='
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
| map(. as $o | .releases | map(. as $r
	| "\($o.code)\t\($o.name)\t\($r.type)\t\($r.date)\t\($r.version)\t\($r.build)"
))
| flatten
'

COLUMNS=(CODE NAME TYPE DATE VERSION BUILD)
{
	(IFS=$'\t'; echo "${COLUMNS[*]}")
	curl -fsS 'https://data.services.jetbrains.com/products' \
		| jq \
			--arg products "${PRODUCTS_LIST[*]}" \
			--arg release_types "$RELEASE_TYPES_RE" \
			--argjson last_n "$LAST_N" \
			". $JQ_PROG []" -r
} | column -Lt -s $'\t'
