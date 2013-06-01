#!/bin/bash

function rewrite_date() {
	read ORIGINAL_DATE_STRING TZ
	date --date="TZ=\"$TZ\" $ORIGINAL_DATE_STRING" -R | sed -e 's/Oct/Nov/g'
}

export GIT_AUTHOR_DATE="$(echo $GIT_AUTHOR_DATE | rewrite_date)"
export GIT_COMMITTER_DATE="$(echo $GIT_COMMITTER_DATE | rewrite_date)"
