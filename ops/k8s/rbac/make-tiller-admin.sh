#!/bin/sh

#
# rbac/make-tiller-admin.sh -- create and grant cluster-admin to tiller service account
#

kubectl create serviceaccount -n kube-system tiller
kubectl create clusterrolebinding make-tiller-admin-again --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
