#!/bin/bash

. lib.sh || exit 1

fail() {
	log "bisect.sh failed: $_ (rc=$?)"
	exit 125
}
trap fail ERR

git reset --hard
git clean -fxd

mkdir pkgdir
scons config
scons -j$(nproc) DEBUG=1 --prefix=$(pwd)/pkgdir/usr --actual-prefix=/usr
scons -j$(nproc) DEBUG=1 --prefix=$(pwd)/pkgdir/usr --actual-prefix=/usr install

coproc pkgdir/usr/bin/rmlint -T df -Dj -vv -o pretty -o summary -o sh:rmlint.sh -c sh:handler=reflink --hidden --xattr --with-fiemap /mnt/data/Media /mnt/data/Torrents 2>&1

rmlint_out="${COPROC[0]}"
rmlint_in="${COPROC[1]}"
rmlint_pid="$COPROC_PID"

< <(<&${rmlint_out} tee /dev/stderr) grep -q "Done shred preprocessing" && found=1 || found=0

kill $rmlint_pid || true
wait $rmlint_pid && rc=0 || rc=$?

if (( found )); then
	log "progressed to matching stage -- ok (rc=$rc)"
	exit 1 # new
else
	log "died before matching stage -- not ok (rc=$rc)"
	exit 0 # old
fi
