#!/bin/bash

set -e

usage() {
	cat >&2 <<EOF
$0 -- configure a Docker registry as the default for the given k8s namespace
      via ImagePullSecrets and patching the service account.

Usage: $0 [--namespace NAMESPACE] [--registry-url URL] [--registry-user USER] [--registry-pass PASS]

Options:
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

ARGS=$(getopt -l "namespace:,registry-url:,registry-user:,registry-pass:" -o '' -- "$@")
if (( "$?" )); then
	usage
	exit 1
fi
eval set -- "$ARGS"

MK_REGISTRY_ARGS=()
NAME=registry
NAMESPACE=

while true; do
	case "$1" in
	# HANDLING HERE
	--namespace)
		MK_REGISTRY_ARGS+=( "$1" "$2" )
		shift
		NAMESPACE="$1"
		;;
	--registry-*)
		MK_REGISTRY_ARGS+=( "$1" "$2" )
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

kubectl delete secret "$NAME" ||:
./registry-mksecret.sh --name "$NAME" "${MK_REGISTRY_ARGS[@]}" | kubectl apply -f -
kubectl patch serviceaccount "${NAMESPACE:-default}" -p "{ \"imagePullSecrets\": [ { \"name\": \"$NAME\" } ] }"

