#!/bin/bash

HELM_INIT_ARGS=( "$@" )

helm2 init --service-account tiller --override 'spec.template.spec.containers[0].command'='{/tiller,--storage=secret}' "${HELM_INIT_ARGS[@]}"
