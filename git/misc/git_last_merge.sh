#!/bin/bash

function git_log_hash() {
	git log --pretty=format:%H "$@"
}

function last_merge() {
	git_log_hash "$1" --date-order --merges -1
}

function since_last_merge() {
	git_log_hash "$(last_merge "$1")..$1"
}

set -e

DEST_BRANCH="$1"
shift

git checkout "$DEST_BRANCH"

for arg; do
	git cherry-pick $(since_last_merge "$arg")
done
