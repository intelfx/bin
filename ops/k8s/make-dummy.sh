#!/bin/bash

#
# make-dummy.sh -- converts a Deployment or a StatefulSet into a dummy by replacing command with `sleep infinity`
#                  and removing any other parts of the definition that execute commands inside the Pod
#                  (i. e. probes and lifecycle hooks).
#

function jq_patch() {
  jq '.spec.template.spec |= ( del(.initContainers) | .containers[] |= ( .command = [ "sleep", "infinity" ] | del(.livenessProbe) | del(.readinessProbe) | del(.lifecycle) ) )'
  #jq '.spec.template.spec |= ( del(.initContainers) | .containers[] |= ( .image = "k8s.gcr.io/pause:3.1" | .imagePullPolicy = "IfNotPresent" | .command = [ "/pause" ] | del(.livenessProbe) | del(.readinessProbe) | del(.lifecycle) ) )'
}

kubectl get "$@" -o json | jq_patch | kubectl replace -f -
kubectl scale "$@" --replicas=0
kubectl scale "$@" --replicas=1
