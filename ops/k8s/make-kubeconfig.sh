#!/bin/bash -e

. lib.sh || exit

kubeget() {
	local jsonpath="$1"
	shift
	kubectl config view -o jsonpath="$jsonpath" "$@"
}

mkreadtemp() {
	local temp="$(mktemp)"
	cat >"$temp"
	echo "$temp"
}


usage() {
	cat <<-EOF
	${0##*/} -- synthesize a kubeconfig.yaml from existing kubectl configuration using a specified service account

	Usage: $0 [--context CONTEXT] --namespace NAMESPACE --service-account SERVICE-ACCOUNT (-O OUTPUT-DIR | -o OUTPUT-FILE)

	EOF
	exit 1
}

declare -A PARSE_ARGS_SPEC
PARSE_ARGS_SPEC=(
	[--context:]="ARG_CONTEXT"
	[--namespace:]="ARG_NAMESPACE"
	[--service-account:]="ARG_SERVICE_ACCOUNT"
	[-O:]="ARG_OUT_DIR"
	[-o:]="ARG_OUT_FILE"
)
parse_args PARSE_ARGS_SPEC "$@"

[[ $ARG_NAMESPACE ]] || usage
[[ $ARG_SERVICE_ACCOUNT ]] || usage
[[ $ARG_OUT_DIR && $ARG_OUT_FILE ]] && usage
[[ $ARG_OUT_DIR || $ARG_OUT_FILE ]] || ARG_OUT_DIR=.
[[ $ARG_CONTEXT ]] || ARG_CONTEXT="$(kubeget "{.current-context}")"

if [[ $ARG_OUT_FILE == "-" ]]; then
	ARG_STDOUT=1
	unset ARG_OUT_FILE
fi

log "Context: $ARG_CONTEXT"
log "Namespace: $ARG_NAMESPACE"
log "Service account: $ARG_SERVICE_ACCOUNT"
if [[ $ARG_OUT_DIR ]]; then
	log "Output directory: $ARG_OUT_DIR"
fi
if [[ $ARG_OUT_FILE ]]; then
	log "Output file: $ARG_OUT_FILE"
fi
if [[ $ARG_STDOUT ]]; then
	log "Writing to stdout"
fi

cleanup() {
	if [[ -e "$KUBE_CLUSTER_CA" ]]; then
		rm -f "$KUBE_CLUSTER_CA"
	fi
	if [[ -e "$KUBECONFIG_TMP" ]]; then
		rm -f "$KUBECONFIG_TMP"
	fi
}
trap cleanup EXIT

# extract cluster information from current context
KUBE_CLUSTER="$(kubeget "{.contexts[?(.name == \"$ARG_CONTEXT\")].context.cluster}")"
KUBE_CLUSTER_ENDPOINT="$(kubeget "{.clusters[?(.name == \"$KUBE_CLUSTER\")].cluster.server}")"
KUBE_CLUSTER_CA="$(kubeget "{.clusters[?(.name == \"$KUBE_CLUSTER\")].cluster.certificate-authority-data}" --raw | base64 -d | mkreadtemp)"

log "Cluster endpoint: $KUBE_CLUSTER_ENDPOINT"
log "Cluster CA: <$KUBE_CLUSTER_CA>"

KUBE_SECRET="$(kubectl get serviceaccount --namespace "$ARG_NAMESPACE" "$ARG_SERVICE_ACCOUNT" -ojson | jq -r '.secrets[0].name')"
log "Service account ($ARG_SERVICE_ACCOUNT) secret: $KUBE_SECRET"
KUBE_TOKEN="$(kubectl get secret --namespace "$ARG_NAMESPACE" "$KUBE_SECRET" -ojson | jq -r '.data["token"]' | base64 -d)"
log "Service account ($ARG_SERVICE_ACCOUNT) token: <${#KUBE_TOKEN} bytes>"

if [[ $ARG_OUT_DIR ]]; then
	KUBECONFIG="$ARG_OUT_DIR/$KUBE_CLUSTER-$ARG_NAMESPACE-$ARG_SERVICE_ACCOUNT.yaml"
elif [[ $ARG_STDOUT ]]; then
	KUBECONFIG_TMP="$(mktemp)"
	KUBECONFIG="$KUBECONFIG_TMP"
else
	KUBECONFIG="$ARG_OUT_FILE"
fi

kubectl config set-cluster "$KUBE_CLUSTER" \
	--kubeconfig "$KUBECONFIG" \
	--server "$KUBE_CLUSTER_ENDPOINT" \
	--certificate-authority "$KUBE_CLUSTER_CA" \
	--embed-certs=true \
	>&2

kubectl config set-credentials "$KUBE_CLUSTER-$ARG_NAMESPACE-$ARG_SERVICE_ACCOUNT" \
	--kubeconfig "$KUBECONFIG" \
	--token "$KUBE_TOKEN" \
	>&2

kubectl config set-context "$KUBE_CLUSTER-$ARG_NAMESPACE-$ARG_SERVICE_ACCOUNT" \
	--kubeconfig "$KUBECONFIG" \
	--cluster "$KUBE_CLUSTER" \
	--user "$KUBE_CLUSTER-$ARG_NAMESPACE-$ARG_SERVICE_ACCOUNT" \
	--namespace "$ARG_NAMESPACE" \
	>&2

kubectl config use-context "$KUBE_CLUSTER-$ARG_NAMESPACE-$ARG_SERVICE_ACCOUNT" \
	--kubeconfig "$KUBECONFIG" \
	>&2

if [[ $ARG_STDOUT ]]; then
	cat "$KUBECONFIG"
fi
