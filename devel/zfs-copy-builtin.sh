#!/bin/bash

set -eo pipefail
shopt -s lastpipe

log() {
	echo "${0##*/}: $*" >&2
}

err() {
	echo "${0##*/}: error: $*" >&2
}

die() {
	err "$@"
	exit 1
}

usage() {
	if (( $# )); then
		echo "${0##*/}: $*" >&2
		echo >&2
	fi
	_usage >&2
	exit 1
}

_usage() {
	cat <<EOF
usage: $0 <kernel source tree>
EOF
}


#
# args
#

case "$#" in
1) KERNEL_DIR="$1" ;;
*) usage "wrong number of positional arguments" ;;
esac


#
# main
#

if ! [[ -e zfs_config.h ]]; then
	err "you did not run configure, or you're not in the ZFS source directory."
	err "run configure with --with-linux=$KERNEL_DIR and --enable-linux-builtin."
	log "./autogen.sh && ./configure --prefix=/usr --with-config=all --with-linux=$KERNEL_DIR --enable-linux-experimental --enable-linux-builtin=yes --disable-debug && $0 $KERNEL_DIR"
	exit 1
fi >&2

if git -C "$KERNEL_DIR" status --porcelain | grep -q '.'; then
	die "kernel tree ($KERNEL_DIR) is dirty, aborting"
fi

make clean ||:
make gitrev

rm -rf "$KERNEL_DIR/include/zfs" "$KERNEL_DIR/fs/zfs"
cp -R include "$KERNEL_DIR/include/zfs"
cp -R module "$KERNEL_DIR/fs/zfs"
cp zfs_config.h -t "$KERNEL_DIR/include/zfs"

log "cleaning up and adding copied ZFS sources to the kernel tree ($KERNEL_DIR)"
set -x

find "$KERNEL_DIR/fs/zfs" "$KERNEL_DIR/include/zfs" \( -name 'Makefile*' -or -name 'Kbuild.*' \) -exec rm -vf {} \+
mv -vf "$KERNEL_DIR/fs/zfs/Kbuild" "$KERNEL_DIR/fs/zfs/Makefile"
sed -r '/zfs_gitrev\.h/d' -i "$KERNEL_DIR/include/zfs/.gitignore"
sed -r '/Kbuild/d' -i "$KERNEL_DIR/fs/zfs/.gitignore"

git -C "$KERNEL_DIR" add -A \
	fs/zfs \
	include/zfs \
	# EOL
git -C "$KERNEL_DIR" commit \
	-m "zfs: add $(git describe --long --tags) ($(git show --no-patch --format='"%s"'))"
{ set +x; } &>/dev/null

log "done. now you can build the kernel with ZFS support."
log "don't forget to add Kbuild integration (c3373c78b9dcbe5cabd94fcba2bcabd3464f6784)."
log "make sure you enable ZFS support (CONFIG_ZFS) before building."
