#!/bin/sh

set -ef

usage()
{
	echo "usage: $0 <kernel source tree>" >&2
	exit 1
}

[ "$#" -eq 1 ] || usage
KERNEL_DIR="$1"

if ! [ -e 'zfs_config.h' ]
then
	echo "$0: you did not run configure, or you're not in the ZFS source directory."
	echo "$0: run configure with --with-linux=$KERNEL_DIR and --enable-linux-builtin."

	exit 1
fi >&2

if git -C "$KERNEL_DIR" status --porcelain | grep -q '.'; then
	echo "$0: kernel tree ($KERNEL_DIR) is dirty, aborting" >&2

	exit 1
fi

make clean ||:
make gitrev

rm -rf "$KERNEL_DIR/include/zfs" "$KERNEL_DIR/fs/zfs"
cp -R include "$KERNEL_DIR/include/zfs"
cp -R module "$KERNEL_DIR/fs/zfs"
cp zfs_config.h -t "$KERNEL_DIR/include/zfs"

echo "$0: cleaning up and adding copied ZFS sources to the kernel tree ($KERNEL_DIR)" >&2
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

echo "$0: done. now you can build the kernel with ZFS support." >&2
echo "$0: don't forget to add Kbuild integration (c3373c78b9dcbe5cabd94fcba2bcabd3464f6784)." >&2
echo "$0: make sure you enable ZFS support (CONFIG_ZFS) before building." >&2
