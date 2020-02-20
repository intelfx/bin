#!/bin/bash

#
# cronjob-trigger.sh -- "triggers" a CronJob by synthesizing a new Job from a given CronJob definition.
#

function jq_make_job() {
	jq '
	.spec.jobTemplate * {
		apiVersion: "batch/v1",
		kind: "Job",
		metadata: {
			name: (.metadata.name + (now | tostring))
		}
	}
	'
}

function jq_rotate() {
	jq --arg tag "$(date +%s)" '
	(
		if .kind == "List" then .items[]
		else .
		end
	) |= (
		(
			if (.kind == "StatefulSet" or .kind == "Deployment") then .spec.template
			else error("unsupported kind: \(.kind)")
			end
		) |= (
			.metadata.annotations += { "x-rotate-timestamp": $tag }
		)
	)
	'
}

kubectl get "$@" -o json | jq_rotate | kubectl replace -f -
