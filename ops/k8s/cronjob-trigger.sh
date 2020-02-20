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

kubectl get "$@" -o json | jq_make_job | kubectl create -f -
