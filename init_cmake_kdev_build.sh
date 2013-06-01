#!/bin/bash

CC=`which clang`
CXX=`which clang++`
CFLAGS="-O4 -emit-llvm"
CXXFLAGS="-O4 -emit-llvm"
LDFLAGS="-O4 -emit-llvm -Wl,-O1,--as-needed,-z,relro,--relax,--hash-style=gnu"

export CC CXX CFLAGS CXXFLAGS LDFLAGS

function handle_err() {
	echo "==== Failed to build $prog. Exiting." >&2
	exit 1
}

trap handle_err ERR

for prog in {kdevplatform,kdevelop,kdev-ninja,kdev-kernel}; do
	mkdir -p "$prog-git-optimize"
	pushd "$prog-git-optimize"
	
	cmake "$HOME/devel/__mainline/Projects/KDE/$prog" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/kde"
	ninja
	ninja
	ninja
	ninja install

	popd
done
