#!/bin/bash

TOOLCHAIN="${1:-arm-unknown-linux-gnueabi}"
TOOLCHAIN_PATH="$HOME/toolchains/$TOOLCHAIN"

CROSS_PREFIX="$TOOLCHAIN-" ./configure --prefix="$TOOLCHAIN_PATH/$TOOLCHAIN/sysroot" "$@"
