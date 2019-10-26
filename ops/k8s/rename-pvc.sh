#!/bin/bash

set -e
. lib.sh || exit 1

cleanup() {
	if [[ -e $pvc_yaml ]]; then
		rm -f "$pvc_yaml"
	fi

	if [[ -e $pv_yaml ]]; then
		rm -f "$pv_yaml"
	fi
}
trap cleanup EXIT

pvc="$1"
log "PVC: '$pvc'"
pvc_yaml="$(mktemp)"

kubectl get pvc "$pvc" -oyaml >"$pvc_yaml"

pv="$(<"$pvc_yaml" yq -r '.spec.volumeName')"
log "PV: '$pv'"
pv_yaml="$(mktemp)"

log "Setting PV to Retain"
kubectl get pv "$pv" -oyaml >"$pv_yaml"
inplace "$pv_yaml" yq -y '.spec.persistentVolumeReclaimPolicy = "Retain"'
kubectl apply -f "$pv_yaml"

log "Deleting PVC"
kubectl delete -f "$pvc_yaml"

log "Clearing PV claimRef"
kubectl get pv "$pv" -oyaml >"$pv_yaml"
inplace "$pv_yaml" yq -y '.spec.claimRef = null'
kubectl apply -f "$pv_yaml"

log "Recreating PVC"
pvc_new="$2"
inplace "$pvc_yaml" yq --arg name "$pvc_new" -y '.metadata.name = $name'
kubectl apply -f "$pvc_yaml"

log "Setting PV to Delete"
kubectl get pv "$pv" -oyaml >"$pv_yaml"
inplace "$pv_yaml" yq -y '.spec.persistentVolumeReclaimPolicy = "Delete"'
kubectl apply -f "$pv_yaml"
