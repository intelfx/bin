#!/bin/bash

[[ "$CROSS" ]] || { echo "\$CROSS is not set" >&2; return 1; }
[[ "$SYSROOT" ]] || { echo "\$SYSROOT is not set" >&2; return 1; }
which "$CROSS-gcc" || { echo "$CROSS-gcc is not in your \$PATH" >&2; return 1; }

export CC="$CROSS-gcc"
export LD="$CROSS-ld"
export CXX="$CROSS-g++"
export AS="$CROSS-as"
export AR="$CROSS-gcc-ar"
export NM="$CROSS-gcc-nm"
export RANLIB="$CROSS-gcc-ranlib"
export COMFLAGS="-Os -pipe -flto -fuse-linker-plugin --sysroot=$SYSROOT"
export CFLAGS="$COMFLAGS"
export CXXFLAGS="$COMFLAGS"
export LDFLAGS="$COMFLAGS -Wl,-O1"

export PKG_CONFIG_SYSROOT_DIR=$SYSROOT
export PKG_CONFIG_LIBDIR=$SYSROOT/usr/lib/pkgconfig PKG_CONFIG_PATH=

export DESTDIR=$SYSROOT

CONFIGURE_ARGS=(--build x86_64-unknown-linux-gnu --host "$CROSS" --prefix=/usr)
function configure() {
	./configure "${CONFIGURE_ARGS[@]}" "$@"
}

cat <<-EOF
Helpful hints to me in the future:
* use 'configure' instead of './configure' -- this is a wrapper
* --prefix is set to /usr
* sometimes configure does not pick up \$SYSROOT -- use --with-PKG=\$SYSROOT/usr/lib
* sometimes build systems need other flags -- strace needs \$ARCH, set it yourself
* working around lack of sysrooted pkg-config:
  - PKG_CONFIG_SYSROOT_DIR is set to \$SYSROOT
  - PKG_CONFIG_LIBDIR is set to \$SYSROOT/usr/lib/pkgconfig, shadowing the host one
  - PKG_CONFIG_PATH is not used (empty)
* DESTDIR is set to \$SYSROOT -- just make install it
* AR, NM, RANLIB are set to -gcc- wrappers to utilize the LTO plugin
* C/CXX/LDFLAGS contain $COMFLAGS

* WARNING: CONTAINS GMO^WLTO :)

EOF
