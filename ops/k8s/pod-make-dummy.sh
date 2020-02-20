#!/bin/bash

#
# make-dummy.sh -- converts a Deployment or a StatefulSet into a dummy by replacing command with `sleep infinity`
#                  and removing any other parts of the definition that execute commands inside the Pod
#                  (i. e. probes and lifecycle hooks).
#

function jq_kind() {
	jq -r '.kind'
}

function jq_patch() {
	jq '
	(
		if .kind == "Pod" then .spec
		elif (.kind == "StatefulSet" or .kind == "Deployment") then .spec.template.spec
		else error("unsupported kind: \(.kind)")
		end
 	) |= ( .
		| del(.initContainers)
		| .containers[] |= ( .
			| .command = [ "sleep", "infinity" ]
			| del(.livenessProbe)
			| del(.readinessProbe)
			| del(.lifecycle)
		)
	)
	'
}

kind=$(kubectl get "$@" -o json | jq_kind)

kubectl get "$@" -o json | jq_patch | kubectl replace -f -
case "$kind" in
Deployment|StatefulSet)
	kubectl scale "$@" --replicas=0
	kubectl scale "$@" --replicas=1
	;;
esac
