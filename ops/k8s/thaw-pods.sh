#!/bin/bash -e

KUBECTL_GET_ARGS=()
KUBECTL_DELETE_ARGS=()

while (( $# )); do
  [[ $1 == -- ]] && { shift; break; }
  KUBECTL_GET_ARGS+=( "$1" )
  shift
done

while (( $# )); do
  [[ $1 == -- ]] && { shift; break; }
  KUBECTL_DELETE_ARGS+=( "$1" )
  shift
done


kubectl get pods "${KUBECTL_GET_ARGS[@]}" -o json \
  | jq -r '.items[] | select(.status.containerStatuses[]?.ready == false) | .metadata.name' \
  | xargs -r kubectl delete pods "${KUBECTL_DELETE_ARGS[@]}"
