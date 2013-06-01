#!/bin/bash
export CC=clang
export CXX=clang++
export CFLAGS="-O3 -flto -march=native"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-O3 -flto -fuse-linker-plugin -Wl,-O1,-z,relro,--as-needed,--relax,--sort-common,--hash-style=gnu"
cmake -DCMAKE_BUILD_TYPE=Release "$@"
