#!/bin/bash

TOOLCHAIN="${1:-arm-unknown-linux-gnueabi}"
TOOLCHAIN_PATH="$HOME/toolchains/$TOOLCHAIN"

PATH="$TOOLCHAIN_PATH/bin:$PATH" ./configure --prefix="$TOOLCHAIN_PATH/$TOOLCHAIN/sysroot" "$@"
