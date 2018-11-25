#!/bin/bash -e

. lib.sh

#
# rbac/make-me-admin.sh [TAG] [USER] -- grant cluster-admin to specified account
#

usage() {
  echo
  cat >&2 <<EOF
$0 -- grant cluster-admin to specified account
Usage: $0 [TAG] [USER]

EOF
  exit 1
}

TAG="$1"
USER="$2"

if ! [[ $TAG ]]; then
  err "Tag not specified"
  usage
fi

if ! [[ $USER ]]; then
  err "User not specified"
  usage
fi

kubectl create clusterrolebinding "make-$1-admin-again" --clusterrole=cluster-admin --user="$2"

