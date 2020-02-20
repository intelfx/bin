#!/bin/bash -e

kubectl get pods "$@" -o json \
  | jq -r '.items[] | select(.status | (.phase == "Failed") and (.reason == "Evicted")) | .metadata.name' \
  | xargs -r kubectl delete pods "$@"
