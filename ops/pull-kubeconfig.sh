#!/bin/bash

. lib.sh || exit

#
# functions
#

yq_kubeconfig() {
	yq -r "$@" "$TMP_FILE"
}

#
# args
#

_usage() {
	cat <<EOF
Usage: $0 [--rename NAME] [[USER@]HOST:]PATH/TO/KUBECONFIG
EOF
}

declare -A ARGS=(
	[--rename]=ARG_RENAME
	[--]=ARGV
)
parse_args ARGS "$@" || usage
(( ${#ARGV[@]} == 1 )) || usage "Expected 1 positional argument, got ${#ARGV[@]}"

TARGET="${ARGV[0]}"
RENAME="$ARG_RENAME"

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
ltrap "rm -f '$TMP_FILE'"

"${RETRIEVE_CMD[@]}" "$TMP_FILE"

yq_kubeconfig '.contexts | length' | read CTX_NR
if (( CTX_NR != 1 )); then
	die "$TARGET defines $CTX_NR != 1 contexts, aborting"
fi

yq_kubeconfig '.contexts[].name' | read CTX_NAME
yq_kubeconfig '.contexts[].context.cluster' | read CTX_CLUSTER
yq_kubeconfig '.contexts[].context.user' | read CTX_USER

if ! [[ $CTX_NAME && $CTX_CLUSTER && $CTX_USER ]]; then
	err "$TARGET has a malformed context definition, aborting:"
	yq_kubeconfig '.contexts[]'
fi

yq_kubeconfig --arg cluster "$CTX_CLUSTER" '
.clusters | map(select(.name == $cluster)) | .[].cluster.server
' | read CLUSTER_SERVER

log "Context: $CTX_NAME"
log "Cluster: $CTX_CLUSTER"
log "User:    $CTX_USER"
log "Server:  $CLUSTER_SERVER"

# Use existing name, if present
for name in "$CTX_NAME" "$CTX_CLUSTER" "$CTX_USER" "$RENAME"; do
	if ! [[ $name == default || $name == admin ]]; then
		break
	fi
done
NEW_NAME="$name"

# Use existing address, if present
if [[ $CLUSTER_SERVER == *127.0.0.1* ]]; then
	NEW_SERVER="${CLUSTER_SERVER/127.0.0.1/$HOST}"
elif [[ $CLUSTER_SERVER == *"[::1]"* ]]; then
	NEW_SERVER="${CLUSTER_SERVER/"[::1]"/$HOST}"
else
	NEW_SERVER="$CLUSTER_SERVER"
fi

if [[ $CTX_NAME != $NEW_NAME || $CTX_CLUSTER != $NEW_NAME || $CTX_USER != $NEW_NAME || $CLUSTER_SERVER != $NEW_SERVER ]]; then
	if [[ $CTX_NAME != $NEW_NAME || $CTX_CLUSTER != $NEW_NAME || $CTX_USER != $NEW_NAME ]]; then
		log "=> New name:   $NEW_NAME"
	fi
	if [[ $CLUSTER_SERVER != $NEW_SERVER ]]; then
		log "=> New server: $NEW_SERVER"
	fi

	yq_kubeconfig -y \
		--arg context "$CTX_NAME" \
		--arg cluster "$CTX_CLUSTER" \
		--arg user "$CTX_USER" \
		--arg new_server "$NEW_SERVER" \
		--arg new_name "$NEW_NAME" \
		'.
		| .clusters |= (.
			| map(select(.name == $cluster))
			| map(.cluster.server |= $new_server)
			| map(.name |= $new_name)
		)
		| .users |= (.
			| map(select(.name == $user))
			| map(.name |= $new_name)
		)
		| .contexts |= [{
			name: $rename,
			context: {
				cluster: $new_name,
				user: $new_name,
			}
		}]
		| .["current-context"] |= $new_name
		' \
	| sponge "$TMP_FILE"

	yq_kubeconfig . "$TMP_FILE"
else
	log "=> Keeping everything as-is"
fi

: ${KUBECONFIG=$HOME/.kube/config}
KUBECONFIG="$TMP_FILE:$KUBECONFIG" kubectl config view --flatten | sponge "$KUBECONFIG"
