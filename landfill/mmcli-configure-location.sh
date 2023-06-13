#!/bin/bash

set -ex -o pipefail

WORKDIR=
cleanup() {
	rm -rf "$WORKDIR"
}
trap cleanup EXIT

WORKDIR="$(mktemp -d)"

curl --proxy socks5h://localhost:1080 -fL 'http://xtrapath5.izatcloud.net/xtra3grcej.bin' -o "$WORKDIR/xtra3grcej.bin"
mmcli -m- --location-set-supl-server=supl.google.com:7276
mmcli -m- --location-inject-assistance-data="$WORKDIR/xtra3grcej.bin"
