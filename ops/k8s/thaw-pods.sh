#!/bin/bash -e

kubectl get pods "$@" -o json \
  | jq -r '.items[] | select(.status.containerStatuses[]?.ready == false) | .metadata.name' \
  | xargs -r kubectl delete pods
