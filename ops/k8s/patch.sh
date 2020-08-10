#!/bin/bash -e

. lib.sh || exit 1

ARG_PATCH=""
ARG_OBJECTS=()
ARG_KUBECTL=()
ARG_JQ=()
ARG_REMAINDER=()

declare -A ARGS
ARGS=(
	[-p:]="ARG_PATCH"
	[--patch:]="ARG_PATCH"
	[--]="ARG_REMAINDER"
)
parse_args ARGS "$@"

if [[ "$ARG_PATCH" ]]; then
	ARG_JQ+=( "$ARG_PATCH" )
fi

set -- "${ARG_REMAINDER[@]}"
while (( $# )); do
	if [[ "$1" == "--" ]]; then shift; break; fi
	ARG_OBJECTS+=( "$1" ); shift
done
while (( $# )); do
	if [[ "$1" == "--" ]]; then shift; break; fi
	ARG_KUBECTL+=( "$1" ); shift
done
ARG_JQ+=( "$@" )

log "kubernetes objects: ${ARG_OBJECTS[@]}"
log "kubectl arguments: ${ARG_KUBECTL[@]}"
log "jq arguments: ${ARG_JQ[@]}"

eval "$(globaltraps)"
MANIFEST_FILE="$(mktemp)"
ltrap "rm -vf '$MANIFEST_FILE'"

log "Fetching manifests"
kubectl get "${ARG_KUBECTL[@]}" "${ARG_OBJECTS[@]}" -ojson >"$MANIFEST_FILE"

log "Demangling list"
LIST=0
if [[ "$(cat "$MANIFEST_FILE" | jq -r '.kind')" == "List" ]]; then
	LIST=1
	inplace jq '.items[]' "$MANIFEST_FILE"
fi

log "Patching manifests"
inplace jq "${ARG_JQ[@]}" "$MANIFEST_FILE"

log "Recreating list"
if (( LIST )); then
	inplace jq --slurp '{ apiVersion: "v1", kind: "List", items: . }' "$MANIFEST_FILE"
fi

log "Applying manifests"
kubectl apply "${ARG_KUBECTL[@]}" -f "$MANIFEST_FILE"
