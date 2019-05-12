#!/bin/bash -e

KUBECTL_GET_ARGS=()

while (( $# )); do
  [[ $1 == -- ]] && { shift; break; }
  KUBECTL_GET_ARGS+=( "$1" )
  shift
done


kubectl get pods "${KUBECTL_GET_ARGS[@]}" -o json \
  | jq -r '.items[] | select(.status.phase != "Succeeded") | select(.status.containerStatuses[]?.ready == false) | .spec.nodeName'
