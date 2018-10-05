#!/bin/bash

set -e

usage() {
	cat >&2 <<EOF
$0 -- generate a k8s docker-registry secret from given parameters,
      more flexible than kubectl create secret docker-registry.

Usage: $0 --name NAME [--namespace NAMESPACE] [--registry-url URL] [--registry-user USER] [--registry-pass PASS]

Options:
	--name NAME
		Use given name

	--namespace NAMESPACE
		Use given namespace

	--registry-url URL
		Use given registry URL

	--registry-user USER
		Use given username to auth with the registry

	--registry-pass PASS
		Use given password to auth with the registry


EOF
}

if ! ARGS=$(getopt -l "name:,namespace:,registry-url:,registry-user:,registry-pass:" -o '' -- "$@"); then
	usage
	exit 1
fi
eval set -- "$ARGS"

NAMESPACE=
NAME=
REGISTRY_URL=
REGISTRY_USER=
REGISTRY_PASS=

while true; do
	case "$1" in
	--name)
		shift
		NAME="$1"
		;;
	--namespace)
		shift
		NAMESPACE="$1"
		;;
	--registry-*)
		var="$(tr 'a-z-' 'A-Z_' <<< "${1#--}")"
		declare -n var
		var="$2"
		declare +n var
		shift
		;;
	--)
		shift
		break
		;;
	*)
		exit 1
		;;
	esac
	shift
done

if [[ ! $NAME || ! $REGISTRY_URL || ( ! $REGISTRY_USER && $REGISTRY_PASS ) || ( $REGISTRY_USER && ! $REGISTRY_PASS ) ]]; then
	echo "Wrong arguments." >&2
	exit 1
fi

# generate header
cat <<EOF
apiVersion: v1
kind: Secret
type: kubernetes.io/dockerconfigjson
metadata:
  name: "$NAME"
EOF
# write namespace if we have it
[[ "$NAMESPACE" ]] && cat <<EOF
  namespace: "$NAMESPACE"
EOF

# piecewise generate the docker config.json
json="{}"
[[ "$REGISTRY_URL" ]] && json+=" + { ServerURL: \"$REGISTRY_URL\" }"
[[ "$REGISTRY_USER" ]] && json+=" + { Username: \"$REGISTRY_USER\" }"
[[ "$REGISTRY_PASS" ]] && json+=" + { Secret: \"$REGISTRY_PASS\" }"

# synthesize the actual json, base64 and write it
cat <<EOF
data:
  .dockerconfigjson: $(jq --null-input --compact-output "$json" | base64 -w 0)
EOF
