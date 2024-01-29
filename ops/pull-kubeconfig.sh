#!/bin/bash

. lib.sh || exit

#
# functions
#

query() {
	yq -r "$@" "$TMP_FILE"
}

#
# args
#

TARGET="$1"
RENAME="$2"

if [[ "$TARGET" =~ ^([^@]+@)?([^/:]+)(:.+)$ ]]; then
	USER="${BASH_REMATCH[1]%'@'}"
	HOST="${BASH_REMATCH[2]}"
	FILE="${BASH_REMATCH[3]#':'}"
	RETRIEVE_CMD=( scp "$TARGET" )
elif [[ -f "$TARGET" ]]; then
	USER="$(whoami)"
	HOST="$(hostname -f)"
	FILE="$TARGET"
	RETRIEVE_CMD=( cp "$TARGET" )
else
	die "Cannot parse target: '$1'"
fi

if ! [[ $RENAME ]]; then
	RENAME="${HOST%%.*}"
fi

#
# main
#

eval "$(globaltraps)"

TMP_FILE="$(mktemp -p "$HOME/.kube" config+XXXXX.yaml)"
cleanup() {
	rm -f "$TMP_FILE"
}
ltrap cleanup

"${RETRIEVE_CMD[@]}" "$TMP_FILE"

query '.contexts | length' | read CTX_NR
if (( CTX_NR != 1 )); then
	die "$TARGET defines $CTX_NR != 1 contexts, aborting"
fi

query '.contexts[].name' | read CTX_NAME
query '.contexts[].context.cluster' | read CTX_CLUSTER
query '.contexts[].context.user' | read CTX_USER

if ! [[ $CTX_NAME && $CTX_CLUSTER && $CTX_USER ]]; then
	err "$TARGET has a malformed context definition, aborting:"
	query '.contexts[]'
fi

query --arg cluster "$CTX_CLUSTER" '
.clusters | map(select(.name == $cluster)) | .[].cluster.server
' | read CLUSTER_SERVER

log "Context: $CTX_NAME"
log "Cluster: $CTX_CLUSTER"
log "User:    $CTX_USER"
log "Server:  $CLUSTER_SERVER"

if [[ $CTX_NAME == default || $CTX_CLUSTER == default || $CTX_USER == default || $CLUSTER_SERVER == *127.0.0.1* ]]; then
	log "=> New name:   $RENAME"
	log "=> New server: $HOST"

	query -y \
		--arg context "$CTX_NAME" \
		--arg cluster "$CTX_CLUSTER" \
		--arg user "$CTX_USER" \
		--arg host "$HOST" \
		--arg rename "$RENAME" \
		'.
	| .clusters |= (.
		| map(select(.name == $cluster))
		| map(.cluster.server |= gsub("127\\.0\\.0\\.1"; $host))
		| map(.name |= $rename)
		)
	| .users |= (.
		| map(select(.name == $user))
		| map(.name |= $rename)
		)
	| .contexts |= [{
		name: $rename,
		context: {
			cluster: $rename,
			user: $rename,
		}
	}]
	| .["current-context"] |= $rename
	' \
	| sponge "$TMP_FILE"

	query . "$TMP_FILE"
else
	log "=> Keeping everything as-is"
fi

: ${KUBECONFIG=$HOME/.kube/config}
KUBECONFIG="$TMP_FILE:$KUBECONFIG" kubectl config view --flatten | sponge "$KUBECONFIG"
