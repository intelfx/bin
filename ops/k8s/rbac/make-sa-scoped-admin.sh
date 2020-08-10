#!/bin/sh

NAMESPACE="$1"
SERVICEACCOUNT="$2"

kubectl create serviceaccount -n "$NAMESPACE" "$SERVICEACCOUNT"
kubectl create rolebinding "make-$NAMESPACE-$SERVICEACCOUNT-admin" --clusterrole=cluster-admin --namespace="$NAMESPACE" --serviceaccount="$NAMESPACE:$SERVICEACCOUNT"
kubectl create rolebinding "make-$NAMESPACE-$SERVICEACCOUNT-view" --clusterrole=view --namespace='kube-system' --serviceaccount="$NAMESPACE:$SERVICEACCOUNT"
