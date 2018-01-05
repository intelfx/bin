#!/bin/bash

function log() {
	echo ":: $*" >&2
}

function warn() {
	echo "W: $*" >&2
}

function err() {
	echo "E: $*" >&2
}

function die() {
	err "$@"
	exit 1
}
